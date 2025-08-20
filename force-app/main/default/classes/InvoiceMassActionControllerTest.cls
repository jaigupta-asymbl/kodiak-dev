@isTest
public class InvoiceMassActionControllerTest {
    
    @TestSetup
    static void setupTestData() {
        Account testAccount1 = new Account(
            Name = 'Test Company 1',
            BillingCity = 'Test City',
            BillingState = 'TX'
        );
        Account testAccount2 = new Account(
            Name = 'Test Company 2',
            BillingCity = 'Test City',
            BillingState = 'CA'
        );
        insert new List<Account>{testAccount1, testAccount2};
        
        Contact billingContact1 = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@testcompany1.com',
            AccountId = testAccount1.Id
        );
        Contact billingContact2 = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'jane.smith@testcompany2.com',
            AccountId = testAccount2.Id
        );
        insert new List<Contact>{billingContact1, billingContact2};
        
        Billing_Profile__c billingProfile1 = new Billing_Profile__c(
            Name = 'Test Billing Profile 1',
            Invoice_Template__c = 'Standard',
            Billing_Contact__c = billingContact1.Id
        );
        Billing_Profile__c billingProfile2 = new Billing_Profile__c(
            Name = 'Test Billing Profile 2',
            Invoice_Template__c = 'Per Diem Summary',
            Billing_Contact__c = billingContact2.Id
        );
        insert new List<Billing_Profile__c>{billingProfile1, billingProfile2};
        
        List<Invoice__c> invoices = new List<Invoice__c>();
        for (Integer i = 1; i <= 2; i++) {
            invoices.add(new Invoice__c(
                Account__c = testAccount1.Id,
                Billing_Profile__c = billingProfile1.Id,
                Invoice_Date__c = Date.today(),
                Total_Amount__c = 1000.00 * i,
                Invoice_Period_Start__c = Date.today().addDays(-7),
                Invoice_Period_End__c = Date.today()
            ));
        }
        for (Integer i = 1; i <= 2; i++) {
            invoices.add(new Invoice__c(
                Account__c = testAccount2.Id,
                Billing_Profile__c = billingProfile2.Id,
                Invoice_Date__c = Date.today(),
                Total_Amount__c = 1500.00 * i,
                Invoice_Period_Start__c = Date.today().addDays(-7),
                Invoice_Period_End__c = Date.today()
            ));
        }
        insert invoices;
    }
    
    @isTest
    static void testSendInvoiceEmails() {
        List<Invoice__c> invoices = [SELECT Id FROM Invoice__c WHERE Account__r.Name = 'Test Company 1'];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : invoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        InvoiceMassActionController.MassActionResult result = InvoiceMassActionController.sendInvoiceEmails(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'Email sending should succeed');
        System.assertEquals(invoiceIds.size(), result.totalInvoices, 'Total invoices should match');
        System.assertEquals(1, result.accountGroups, 'Should have 1 account group');
    }
    
    @isTest
    static void testSendInvoiceEmailsMultipleAccounts() {
        List<Invoice__c> invoices = [SELECT Id FROM Invoice__c];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : invoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        InvoiceMassActionController.MassActionResult result = InvoiceMassActionController.sendInvoiceEmails(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'Email sending should succeed');
        System.assertEquals(invoiceIds.size(), result.totalInvoices, 'Total invoices should match');
        System.assertEquals(2, result.accountGroups, 'Should have 2 account groups');
        System.assert(!result.warnings.isEmpty(), 'Should have warnings for multiple accounts');
    }
    
    @isTest
    static void testSendInvoiceEmailsEmptyList() {
        List<Id> emptyList = new List<Id>();
        
        Test.startTest();
        InvoiceMassActionController.MassActionResult result = InvoiceMassActionController.sendInvoiceEmails(emptyList);
        Test.stopTest();
        
        System.assert(!result.success, 'Empty list should fail');
        System.assertEquals('No invoices selected', result.message, 'Should have appropriate error message');
    }
    
    @isTest
    static void testGenerateInvoicePDFs() {
        List<Invoice__c> invoices = [SELECT Id FROM Invoice__c LIMIT 2];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : invoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        InvoiceMassActionController.MassActionResult result = InvoiceMassActionController.generateInvoicePDFs(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'PDF generation should succeed');
        System.assertEquals(invoiceIds.size(), result.totalInvoices, 'Total invoices should match');
        System.assert(result.message.contains('Successfully generated'), 'Should have success message');
    }
    
    @isTest
    static void testGetInvoicePreview() {
        List<Invoice__c> invoices = [SELECT Id FROM Invoice__c LIMIT 2];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : invoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        List<Invoice__c> previewInvoices = InvoiceMassActionController.getInvoicePreview(invoiceIds);
        Test.stopTest();
        
        System.assertEquals(invoiceIds.size(), previewInvoices.size(), 'Preview should return all requested invoices');
        System.assertNotEquals(null, previewInvoices[0].Account__r.Name, 'Should include account information');
        System.assertNotEquals(null, previewInvoices[0].Billing_Profile__r.Name, 'Should include billing profile information');
    }
    
    @isTest
    static void testValidateInvalidInvoices() {
        Account testAccount = new Account(
            Name = 'Invalid Test Account',
            BillingCity = 'Test City',
            BillingState = 'TX'
        );
        insert testAccount;
        
        Invoice__c invalidInvoice = new Invoice__c(
            Account__c = testAccount.Id,
            Invoice_Date__c = Date.today(),
            Total_Amount__c = 1000.00
        );
        insert invalidInvoice;
        
        Test.startTest();
        InvoiceMassActionController.MassActionResult result = InvoiceMassActionController.sendInvoiceEmails(new List<Id>{invalidInvoice.Id});
        Test.stopTest();
        
        System.assert(!result.success, 'Should fail for invalid invoice');
        System.assert(result.message.contains('No Billing Profile'), 'Should indicate missing billing profile');
    }
}