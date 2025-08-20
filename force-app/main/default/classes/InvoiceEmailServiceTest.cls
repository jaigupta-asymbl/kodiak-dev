@isTest
public class InvoiceEmailServiceTest {
    
    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Test Company',
            BillingCity = 'Test City',
            BillingState = 'TX'
        );
        insert testAccount;
        
        Contact billingContact = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@testcompany.com',
            AccountId = testAccount.Id
        );
        insert billingContact;
        
        Billing_Profile__c billingProfile = new Billing_Profile__c(
            Name = 'Test Billing Profile',
            Invoice_Template__c = 'Standard',
            Billing_Contact__c = billingContact.Id
        );
        insert billingProfile;
        
        List<Invoice__c> invoices = new List<Invoice__c>();
        for (Integer i = 1; i <= 3; i++) {
            invoices.add(new Invoice__c(
                Account__c = testAccount.Id,
                Billing_Profile__c = billingProfile.Id,
                Invoice_Date__c = Date.today(),
                Total_Amount__c = 1000.00 * i,
                Invoice_Period_Start__c = Date.today().addDays(-7),
                Invoice_Period_End__c = Date.today()
            ));
        }
        insert invoices;
        
        Contact ccContact = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'jane.smith@testcompany.com',
            AccountId = testAccount.Id
        );
        insert ccContact;
        
        Additional_Emails__c additionalEmail = new Additional_Emails__c(
            Billing_Profile__c = billingProfile.Id,
            Contact__c = ccContact.Id,
            Type__c = 'CC'
        );
        insert additionalEmail;
    }
    
    @isTest
    static void testSendInvoicesByAccount() {
        List<Invoice__c> invoices = [SELECT Id FROM Invoice__c];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : invoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        InvoiceEmailService.EmailResult result = InvoiceEmailService.sendInvoicesByAccount(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'Email sending should succeed');
        System.assertEquals(1, result.emailsSent, 'Should send 1 email for 1 account group');
        System.assert(result.failedInvoices.isEmpty(), 'No invoices should fail');
    }
    
    @isTest
    static void testSendInvoicesEmptyList() {
        List<Id> emptyList = new List<Id>();
        
        Test.startTest();
        InvoiceEmailService.EmailResult result = InvoiceEmailService.sendInvoicesByAccount(emptyList);
        Test.stopTest();
        
        System.assert(result.success, 'Empty list should not cause error');
        System.assertEquals(0, result.emailsSent, 'No emails should be sent');
    }
    
    @isTest
    static void testSendInvoicesWithoutBillingContact() {
        Billing_Profile__c billingProfile = [SELECT Id FROM Billing_Profile__c LIMIT 1];
        billingProfile.Billing_Contact__c = null;
        update billingProfile;
        
        List<Invoice__c> invoices = [SELECT Id FROM Invoice__c];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : invoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        InvoiceEmailService.EmailResult result = InvoiceEmailService.sendInvoicesByAccount(invoiceIds);
        Test.stopTest();
        
        System.assertEquals(0, result.emailsSent, 'No emails should be sent without billing contact');
    }
}