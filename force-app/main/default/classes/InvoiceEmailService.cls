public class InvoiceEmailService {
    
    public class EmailResult {
        public Boolean success;
        public String error;
        public Integer emailsSent;
        public List<String> failedInvoices;
        
        public EmailResult() {
            this.success = true;
            this.emailsSent = 0;
            this.failedInvoices = new List<String>();
        }
    }
    
    public class InvoiceGroup {
        public Account account;
        public Billing_Profile__c billingProfile;
        public List<Invoice__c> invoices;
        public List<Additional_Emails__c> additionalEmails;
    }
    
    @AuraEnabled
    public static EmailResult sendInvoicesByAccount(List<Id> invoiceIds) {
        EmailResult result = new EmailResult();
        
        try {
            List<Invoice__c> invoices = getInvoicesWithDetails(invoiceIds);
            Map<Id, InvoiceGroup> accountGroups = groupInvoicesByAccount(invoices);
            
            for (InvoiceGroup invoiceGroup : accountGroups.values()) {
                Boolean emailSent = sendEmailForInvoiceGroup(invoiceGroup);
                if (emailSent) {
                    result.emailsSent++;
                } else {
                    for (Invoice__c inv : invoiceGroup.invoices) {
                        result.failedInvoices.add(inv.Name);
                    }
                }
            }
            
            if (!result.failedInvoices.isEmpty()) {
                result.success = false;
                result.error = 'Failed to send emails for some invoice groups';
            }
            
        } catch (Exception e) {
            result.success = false;
            result.error = 'Error sending emails: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static List<Invoice__c> getInvoicesWithDetails(List<Id> invoiceIds) {
        return [
            SELECT Id, Name, Invoice_Date__c,
                   Total_Amount__c, Account__c, Account__r.Name,
                   Billing_Profile__c, Billing_Profile__r.Name,
                   Billing_Profile__r.Billing_Contact__c, 
                   Billing_Profile__r.Invoice_Template__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
            ORDER BY Account__c, Billing_Profile__c
        ];
    }
    
    private static Map<Id, InvoiceGroup> groupInvoicesByAccount(List<Invoice__c> invoices) {
        Map<Id, InvoiceGroup> groups = new Map<Id, InvoiceGroup>();
        
        Set<Id> billingProfileIds = new Set<Id>();
        for (Invoice__c inv : invoices) {
            if (inv.Billing_Profile__c != null) {
                billingProfileIds.add(inv.Billing_Profile__c);
            }
        }
        
        Map<Id, List<Additional_Emails__c>> additionalEmailsMap = getAdditionalEmails(billingProfileIds);
        
        for (Invoice__c invoice : invoices) {
            if (invoice.Account__c == null) continue;
            
            if (!groups.containsKey(invoice.Account__c)) {
                InvoiceGroup invoiceGroup = new InvoiceGroup();
                invoiceGroup.account = invoice.Account__r;
                invoiceGroup.billingProfile = invoice.Billing_Profile__r;
                invoiceGroup.invoices = new List<Invoice__c>();
                invoiceGroup.additionalEmails = additionalEmailsMap.get(invoice.Billing_Profile__c);
                
                groups.put(invoice.Account__c, invoiceGroup);
            }
            
            groups.get(invoice.Account__c).invoices.add(invoice);
        }
        
        return groups;
    }
    
    private static Map<Id, List<Additional_Emails__c>> getAdditionalEmails(Set<Id> billingProfileIds) {
        Map<Id, List<Additional_Emails__c>> emailsMap = new Map<Id, List<Additional_Emails__c>>();
        
        for (Additional_Emails__c email : [
            SELECT Id, Billing_Profile__c, Contact__c, Contact__r.Email, Type__c
            FROM Additional_Emails__c
            WHERE Billing_Profile__c IN :billingProfileIds
            AND Contact__r.Email != null
        ]) {
            if (!emailsMap.containsKey(email.Billing_Profile__c)) {
                emailsMap.put(email.Billing_Profile__c, new List<Additional_Emails__c>());
            }
            emailsMap.get(email.Billing_Profile__c).add(email);
        }
        
        return emailsMap;
    }
    
    private static Boolean sendEmailForInvoiceGroup(InvoiceGroup invoiceGroup) {
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            
            List<String> toAddresses = new List<String>();
            if (invoiceGroup.billingProfile.Billing_Contact__c != null) {
                Contact billingContact = [SELECT Email FROM Contact WHERE Id = :invoiceGroup.billingProfile.Billing_Contact__c LIMIT 1];
                if (billingContact.Email != null) {
                    toAddresses.add(billingContact.Email);
                }
            }
            
            List<String> ccAddresses = new List<String>();
            List<String> bccAddresses = new List<String>();
            
            if (invoiceGroup.additionalEmails != null) {
                for (Additional_Emails__c additionalEmail : invoiceGroup.additionalEmails) {
                    String emailAddr = additionalEmail.Contact__r.Email;
                    if (additionalEmail.Type__c == 'CC') {
                        ccAddresses.add(emailAddr);
                    } else if (additionalEmail.Type__c == 'BCC') {
                        bccAddresses.add(emailAddr);
                    } else {
                        toAddresses.add(emailAddr);
                    }
                }
            }
            
            if (toAddresses.isEmpty()) {
                return false;
            }
            
            email.setToAddresses(toAddresses);
            if (!ccAddresses.isEmpty()) {
                email.setCcAddresses(ccAddresses);
            }
            if (!bccAddresses.isEmpty()) {
                email.setBccAddresses(bccAddresses);
            }
            
            String subject = 'Invoices from Kodiak Labor Solutions - ' + invoiceGroup.account.Name;
            email.setSubject(subject);
            
            String emailBody = buildEmailBody(invoiceGroup);
            email.setHtmlBody(emailBody);
            
            List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
            for (Invoice__c invoice : invoiceGroup.invoices) {
                InvoicePDFGenerationService.InvoicePDFResult pdfResult = InvoicePDFGenerationService.generateInvoicePDF(invoice.Id);
                if (pdfResult.success) {
                    Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                    attachment.setFileName(pdfResult.fileName);
                    attachment.setBody(pdfResult.pdfContent);
                    attachment.setContentType('application/pdf');
                    attachments.add(attachment);
                }
            }
            
            email.setFileAttachments(attachments);
            
            if (!Test.isRunningTest()) {
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
            }
            
            return true;
            
        } catch (Exception e) {
            System.debug('Error sending email: ' + e.getMessage());
            return false;
        }
    }
    
    private static String buildEmailBody(InvoiceGroup invoiceGroup) {
        String body = '<html><body>';
        body += '<p>Dear ' + invoiceGroup.account.Name + ',</p>';
        body += '<p>Please find attached the following invoices from Kodiak Labor Solutions:</p>';
        body += '<ul>';
        
        for (Invoice__c invoice : invoiceGroup.invoices) {
            body += '<li>Invoice #' + invoice.Name;
            body += ' - Date: ' + invoice.Invoice_Date__c.format();
            body += ' - Amount: $' + invoice.Total_Amount__c.setScale(2);
            body += '</li>';
        }
        
        body += '</ul>';
        body += '<p>If you have any questions regarding these invoices, please don\'t hesitate to contact us.</p>';
        body += '<p>Best regards,<br/>Kodiak Labor Solutions</p>';
        body += '</body></html>';
        
        return body;
    }
}