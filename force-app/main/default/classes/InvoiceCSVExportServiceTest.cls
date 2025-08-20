@isTest
public class InvoiceCSVExportServiceTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Export Company',
            AccountNumber = '1023250'
        );
        insert testAccount;
        
        // Create billing profile
        Billing_Profile__c billingProfile = new Billing_Profile__c(
            Name = 'Test Export Billing Profile'
        );
        insert billingProfile;
        
        // Create test invoices with different statuses
        List<Invoice__c> invoices = new List<Invoice__c>();
        
        // Finalized invoices (ready for export)
        for (Integer i = 1; i <= 3; i++) {
            invoices.add(new Invoice__c(
                Account__c = testAccount.Id,
                Billing_Profile__c = billingProfile.Id,
                Status__c = 'Finalized',
                Invoice_Date__c = Date.today().addDays(-i),
                Total_Amount__c = 1000.00 * i,
                Invoice_Period_Start__c = Date.today().addDays(-14),
                Invoice_Period_End__c = Date.today().addDays(-7)
            ));
        }
        
        // Non-finalized invoices (should not appear)
        invoices.add(new Invoice__c(
            Account__c = testAccount.Id,
            Billing_Profile__c = billingProfile.Id,
            Status__c = 'Ready',
            Invoice_Date__c = Date.today(),
            Total_Amount__c = 500.00
        ));
        
        invoices.add(new Invoice__c(
            Account__c = testAccount.Id,
            Billing_Profile__c = billingProfile.Id,
            Status__c = 'Exported',
            Invoice_Date__c = Date.today().addDays(-1),
            Total_Amount__c = 750.00
        ));
        
        insert invoices;
        
        // Create invoice line items for the first finalized invoice
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();
        Invoice__c firstInvoice = [SELECT Id FROM Invoice__c WHERE Status__c = 'Finalized' LIMIT 1];
        
        lineItems.add(new Invoice_Line_Item__c(
            Invoice__c = firstInvoice.Id,
            Description__c = 'Test Line Item 1',
            Quantity__c = 40,
            Unit_Price__c = 25.00,
            Amount__c = 1000.00,
            Date_Worked__c = Date.today().addDays(-7)
        ));
        
        lineItems.add(new Invoice_Line_Item__c(
            Invoice__c = firstInvoice.Id,
            Description__c = 'Test Line Item 2',
            Quantity__c = 8,
            Unit_Price__c = 30.00,
            Amount__c = 240.00,
            Date_Worked__c = Date.today().addDays(-6)
        ));
        
        insert lineItems;
    }
    
    @isTest
    static void testGetFinalizedInvoices() {
        Test.startTest();
        List<Invoice__c> result = InvoiceCSVExportService.getFinalizedInvoices();
        Test.stopTest();
        
        System.assertEquals(3, result.size(), 'Should return only finalized invoices');
        
        for (Invoice__c invoice : result) {
            System.assertEquals('Finalized', invoice.Status__c, 'All invoices should be finalized');
        }
    }
    
    @isTest 
    static void testExportInvoicesToCSVSuccess() {
        List<Invoice__c> finalizedInvoices = [SELECT Id FROM Invoice__c WHERE Status__c = 'Finalized'];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : finalizedInvoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        InvoiceCSVExportService.ExportResult result = InvoiceCSVExportService.exportInvoicesToCSV(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'Export should succeed: ' + result.message);
        System.assertEquals(3, result.invoicesExported, 'Should export 3 invoices');
        System.assertNotEquals(null, result.csvContent, 'CSV content should not be null');
        System.assertNotEquals(null, result.fileName, 'File name should not be null');
        System.assert(result.fileName.contains('Kodiak_Invoice_Export_'), 'File name should contain prefix');
        System.assert(result.fileName.endsWith('.csv'), 'File name should end with .csv');
        
        // Verify invoice status was updated to Exported
        List<Invoice__c> updatedInvoices = [SELECT Id, Status__c FROM Invoice__c WHERE Id IN :invoiceIds];
        for (Invoice__c invoice : updatedInvoices) {
            System.assertEquals('Exported', invoice.Status__c, 'Invoice status should be updated to Exported');
        }
    }
    
    @isTest
    static void testExportInvoicesToCSVEmptyList() {
        List<Id> emptyList = new List<Id>();
        
        Test.startTest();
        InvoiceCSVExportService.ExportResult result = InvoiceCSVExportService.exportInvoicesToCSV(emptyList);
        Test.stopTest();
        
        System.assert(!result.success, 'Export should fail for empty list');
        System.assertEquals('No invoices selected for export', result.message);
        System.assertEquals(0, result.invoicesExported, 'Should export 0 invoices');
    }
    
    @isTest
    static void testExportInvoicesNonFinalized() {
        List<Invoice__c> nonFinalizedInvoices = [SELECT Id FROM Invoice__c WHERE Status__c != 'Finalized'];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : nonFinalizedInvoices) {
            invoiceIds.add(inv.Id);
        }
        
        Test.startTest();
        InvoiceCSVExportService.ExportResult result = InvoiceCSVExportService.exportInvoicesToCSV(invoiceIds);
        Test.stopTest();
        
        System.assert(!result.success, 'Export should fail for non-finalized invoices');
        System.assertEquals('No valid invoices found for export', result.message);
        System.assertEquals(0, result.invoicesExported, 'Should export 0 invoices');
    }
    
    @isTest
    static void testCSVContentGeneration() {
        List<Invoice__c> finalizedInvoices = [
            SELECT Id, Name, Invoice_Date__c, Total_Amount__c, 
                   Account__r.AccountNumber,
                   (SELECT Id, Description__c, Quantity__c, Unit_Price__c, Amount__c 
                    FROM Invoice_Line_Items__r)
            FROM Invoice__c 
            WHERE Status__c = 'Finalized' 
            LIMIT 1
        ];
        
        List<Id> invoiceIds = new List<Id>();
        invoiceIds.add(finalizedInvoices[0].Id);
        
        Test.startTest();
        InvoiceCSVExportService.ExportResult result = InvoiceCSVExportService.exportInvoicesToCSV(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'Export should succeed');
        System.assertNotEquals(null, result.csvContent, 'CSV content should not be null');
        
        // Verify CSV has headers
        String[] lines = result.csvContent.split('\n');
        System.assert(lines.size() > 1, 'CSV should have header and data rows');
        
        // Verify header contains expected columns (from our test metadata)
        String headerLine = lines[0];
        System.assert(headerLine.contains('[Sequence]'), 'Header should contain Sequence column');
    }
    
    @isTest
    static void testCSVFieldMappingRetrieval() {
        // This tests the getCSVFieldMappings method indirectly through export
        List<Invoice__c> finalizedInvoices = [SELECT Id FROM Invoice__c WHERE Status__c = 'Finalized' LIMIT 1];
        List<Id> invoiceIds = new List<Id>();
        invoiceIds.add(finalizedInvoices[0].Id);
        
        Test.startTest();
        InvoiceCSVExportService.ExportResult result = InvoiceCSVExportService.exportInvoicesToCSV(invoiceIds);
        Test.stopTest();
        
        // If we get here without exceptions, the field mapping retrieval worked
        System.assert(result.success, 'Export should succeed with field mappings');
    }
    
    @isTest
    static void testInvoiceWithoutLineItems() {
        // Create an invoice without line items
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Billing_Profile__c billingProfile = [SELECT Id FROM Billing_Profile__c LIMIT 1];
        
        Invoice__c invoiceWithoutItems = new Invoice__c(
            Account__c = testAccount.Id,
            Billing_Profile__c = billingProfile.Id,
            Status__c = 'Finalized',
            Invoice_Date__c = Date.today(),
            Total_Amount__c = 500.00
        );
        insert invoiceWithoutItems;
        
        List<Id> invoiceIds = new List<Id>{ invoiceWithoutItems.Id };
        
        Test.startTest();
        InvoiceCSVExportService.ExportResult result = InvoiceCSVExportService.exportInvoicesToCSV(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'Export should succeed even without line items');
        System.assertEquals(1, result.invoicesExported, 'Should export 1 invoice');
        
        // Verify CSV content exists
        System.assertNotEquals(null, result.csvContent, 'CSV content should not be null');
        String[] lines = result.csvContent.split('\n');
        System.assertEquals(2, lines.size(), 'Should have header + 1 data row for invoice without line items');
    }
    
    @isTest
    static void testStatusUpdateAfterExport() {
        List<Invoice__c> originalInvoices = [SELECT Id, Status__c FROM Invoice__c WHERE Status__c = 'Finalized'];
        List<Id> invoiceIds = new List<Id>();
        for (Invoice__c inv : originalInvoices) {
            invoiceIds.add(inv.Id);
        }
        
        // Verify initial status
        for (Invoice__c inv : originalInvoices) {
            System.assertEquals('Finalized', inv.Status__c, 'Initial status should be Finalized');
        }
        
        Test.startTest();
        InvoiceCSVExportService.ExportResult result = InvoiceCSVExportService.exportInvoicesToCSV(invoiceIds);
        Test.stopTest();
        
        System.assert(result.success, 'Export should succeed');
        
        // Verify status was updated
        List<Invoice__c> updatedInvoices = [SELECT Id, Status__c FROM Invoice__c WHERE Id IN :invoiceIds];
        for (Invoice__c inv : updatedInvoices) {
            System.assertEquals('Exported', inv.Status__c, 'Status should be updated to Exported after export');
        }
    }
}