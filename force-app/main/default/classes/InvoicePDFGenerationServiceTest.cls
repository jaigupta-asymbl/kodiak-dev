@isTest
public class InvoicePDFGenerationServiceTest {
    
    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(
            Name = 'Test Company',
            BillingCity = 'Test City',
            BillingState = 'TX'
        );
        insert testAccount;
        
        Billing_Profile__c billingProfile = new Billing_Profile__c(
            Name = 'Test Billing Profile',
            Invoice_Template__c = 'Standard'
        );
        insert billingProfile;
        
        Invoice__c invoice = new Invoice__c(
            Account__c = testAccount.Id,
            Billing_Profile__c = billingProfile.Id,
            Invoice_Date__c = Date.today(),
            Total_Amount__c = 1000.00,
            Invoice_Period_Start__c = Date.today().addDays(-7),
            Invoice_Period_End__c = Date.today()
        );
        insert invoice;
    }
    
    @isTest
    static void testGenerateStandardInvoicePDF() {
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        
        Test.startTest();
        InvoicePDFGenerationService.InvoicePDFResult result = InvoicePDFGenerationService.generateInvoicePDF(invoice.Id);
        Test.stopTest();
        
        System.assert(result.success, 'PDF generation should succeed');
        System.assertNotEquals(null, result.pdfContent, 'PDF content should not be null');
        System.assertNotEquals(null, result.fileName, 'File name should not be null');
    }
    
    @isTest
    static void testGeneratePerDiemSummaryInvoicePDF() {
        Invoice__c invoice = [SELECT Id, Billing_Profile__c FROM Invoice__c LIMIT 1];
        
        Billing_Profile__c billingProfile = [SELECT Id FROM Billing_Profile__c WHERE Id = :invoice.Billing_Profile__c];
        billingProfile.Invoice_Template__c = 'Per Diem Summary';
        update billingProfile;
        
        Test.startTest();
        InvoicePDFGenerationService.InvoicePDFResult result = InvoicePDFGenerationService.generateInvoicePDF(invoice.Id);
        Test.stopTest();
        
        System.assert(result.success, 'PDF generation should succeed');
        System.assertNotEquals(null, result.pdfContent, 'PDF content should not be null');
    }
    
    @isTest
    static void testGeneratePDFInvalidInvoice() {
        Id fakeInvoiceId = '001000000000000';
        
        Test.startTest();
        InvoicePDFGenerationService.InvoicePDFResult result = InvoicePDFGenerationService.generateInvoicePDF(fakeInvoiceId);
        Test.stopTest();
        
        System.assert(!result.success, 'PDF generation should fail for invalid invoice');
        System.assertEquals('Invoice not found', result.error, 'Error message should indicate invoice not found');
    }
    
    @isTest
    static void testDownloadInvoicePDF() {
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        
        Test.startTest();
        InvoicePDFGenerationService.InvoicePDFResult result = InvoicePDFGenerationService.downloadInvoicePDF(invoice.Id);
        Test.stopTest();
        
        System.assert(result.success, 'PDF download should succeed');
        System.assertNotEquals(null, result.pdfContent, 'PDF content should not be null');
    }
}