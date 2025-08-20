@isTest
private class CraftRateTriggerTest {
    
    // Test data setup method
    private static TestData setupTestData() {
        // Create test data container
        TestData data = new TestData();
        
        // Create test account
        data.testAccount = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Test Street',
            BillingCity = 'Test City',
            BillingState = 'TS',
            BillingPostalCode = '12345',
            BillingCountry = 'Test Country'
        );
        insert data.testAccount;
        
        // Create test opportunity
        data.testOpportunity = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = data.testAccount.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Discovery',
            Expected_Hours_Week__c = '40',
            Expected_Job_Duration__c = '1 Week'
            
        );
        insert data.testOpportunity;
        
        // Create a product for OLIs
        data.testProduct = new Product2(
            Name = 'Test Product',
            IsActive = true
        );
        insert data.testProduct;
        
        // Create a standard price book entry
        data.standardPriceBookEntry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = data.testProduct.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert data.standardPriceBookEntry;
        
        return data;
    }
    
    // Helper class to hold test data
    private class TestData {
        public Account testAccount;
        public Opportunity testOpportunity;
        public Product2 testProduct;
        public PricebookEntry standardPriceBookEntry;
        public List<OpportunityLineItem> hourlyOLIs = new List<OpportunityLineItem>();
        public List<OpportunityLineItem> perPersonOLIs = new List<OpportunityLineItem>();
    }
    
    @isTest
    static void testInsertOLIs() {
        // Setup test data
        TestData data = setupTestData();
        
        // Start the test
        Test.startTest();
        
        // Create hourly OLIs (craftspeople)
        OpportunityLineItem hourlyOLI = new OpportunityLineItem(
            OpportunityId = data.testOpportunity.Id,
            PricebookEntryId = data.standardPriceBookEntry.Id,
            Quantity = 5,
            TotalPrice = 500,
            Ave_Bill_Rate__c = 100,
            Billing_Type__c = 'Hourly'
        );
        insert hourlyOLI;
        
        // Create per person OLI
        OpportunityLineItem perPersonOLI = new OpportunityLineItem(
            OpportunityId = data.testOpportunity.Id,
            PricebookEntryId = data.standardPriceBookEntry.Id,
            Quantity = 1,
            UnitPrice = 200,
            Billing_Type__c = 'Per Person'
        );
        insert perPersonOLI;
        
        Test.stopTest();
        
        // Verify results
        // Check that the per person OLI was updated correctly
        OpportunityLineItem updatedPerPersonOLI = [
            SELECT Project_Craft_Value_pp__c
            FROM OpportunityLineItem
            WHERE Id = :perPersonOLI.Id
        ];
        System.assertEquals(1000, updatedPerPersonOLI.Project_Craft_Value_pp__c, 
                           'Per Person OLI should have Project_Craft_Value_pp__c = 200 * 5 = 1000');
        
        // Check that the opportunity was updated correctly
        Opportunity updatedOpportunity = [
            SELECT Opportunity_Value__c
            FROM Opportunity
            WHERE Id = :data.testOpportunity.Id
        ];
        System.assertEquals(21000, updatedOpportunity.Opportunity_Value__c, 
                           'Opportunity value should be sum of hourly (20000) and per person (1000) values');
    }
    
    @isTest
    static void testUpdateOLIs() {
        // Setup test data
        TestData data = setupTestData();
        
        // Create initial OLIs
        OpportunityLineItem hourlyOLI = new OpportunityLineItem(
            OpportunityId = data.testOpportunity.Id,
            PricebookEntryId = data.standardPriceBookEntry.Id,
            Quantity = 3,
            UnitPrice = 100,
            Billing_Type__c = 'Hourly'
        );
        insert hourlyOLI;
        
        OpportunityLineItem perPersonOLI = new OpportunityLineItem(
            OpportunityId = data.testOpportunity.Id,
            PricebookEntryId = data.standardPriceBookEntry.Id,
            Quantity = 1,
            UnitPrice = 200,
            Billing_Type__c = 'Per Person'
        );
        insert perPersonOLI;
        
        // Reset any triggers/DML operations
        Test.getEventBus().deliver();
        
        // Start the test
        Test.startTest();
        
        // Update hourly OLI quantity
        hourlyOLI.Quantity = 5;
        hourlyOLI.TotalPrice = 500;
        
        update hourlyOLI;
        
        Test.stopTest();
        
        // Verify results
        // Check that the per person OLI was updated correctly
        OpportunityLineItem updatedPerPersonOLI = [
            SELECT Project_Craft_Value_pp__c
            FROM OpportunityLineItem
            WHERE Id = :perPersonOLI.Id
        ];
        System.assertEquals(1000, updatedPerPersonOLI.Project_Craft_Value_pp__c, 
                           'Per Person OLI should have Project_Craft_Value_pp__c = 200 * 5 = 1000');
        
        // Check that the opportunity was updated correctly
        Opportunity updatedOpportunity = [
            SELECT Opportunity_Value__c
            FROM Opportunity
            WHERE Id = :data.testOpportunity.Id
        ];
        System.assertEquals(21000, updatedOpportunity.Opportunity_Value__c, 
                           'Opportunity value should be sum of hourly (20000) and per person (1000) values');
    }
    
    @isTest
    static void testDeleteOLIs() {
        // Setup test data
        TestData data = setupTestData();
        
        // Create initial OLIs
        OpportunityLineItem hourlyOLI1 = new OpportunityLineItem(
            OpportunityId = data.testOpportunity.Id,
            PricebookEntryId = data.standardPriceBookEntry.Id,
            Quantity = 3,
            Ave_Bill_Rate__c = 100,
            TotalPrice = 300,
            Billing_Type__c = 'Hourly'
        );
        
        OpportunityLineItem hourlyOLI2 = new OpportunityLineItem(
            OpportunityId = data.testOpportunity.Id,
            PricebookEntryId = data.standardPriceBookEntry.Id,
            Quantity = 2,
            Ave_Bill_Rate__c = 100,
            UnitPrice = 100,
            Billing_Type__c = 'Hourly'
        );
        
        insert new List<OpportunityLineItem>{hourlyOLI1, hourlyOLI2};
        
        OpportunityLineItem perPersonOLI = new OpportunityLineItem(
            OpportunityId = data.testOpportunity.Id,
            PricebookEntryId = data.standardPriceBookEntry.Id,
            Quantity = 1,
            UnitPrice = 200,
            Billing_Type__c = 'Per Person'
        );
        insert perPersonOLI;
        
        // Reset any triggers/DML operations
        Test.getEventBus().deliver();
        
        // Start the test
        Test.startTest();
        
        // Delete one of the hourly OLIs
        delete hourlyOLI1;
        
        Test.stopTest();
        
        // Verify results
        // Check that the per person OLI was updated correctly
        OpportunityLineItem updatedPerPersonOLI = [
            SELECT Project_Craft_Value_pp__c
            FROM OpportunityLineItem
            WHERE Id = :perPersonOLI.Id
        ];
        System.assertEquals(400, updatedPerPersonOLI.Project_Craft_Value_pp__c, 
                           'Per Person OLI should have Project_Craft_Value_pp__c = 200 * 2 = 400');
        
        // Check that the opportunity was updated correctly
        Opportunity updatedOpportunity = [
            SELECT Opportunity_Value__c
            FROM Opportunity
            WHERE Id = :data.testOpportunity.Id
        ];
        System.assertEquals(8400, updatedOpportunity.Opportunity_Value__c, 
                           'Opportunity value should be sum of remaining hourly (8000) and per person (400) values');
    }
    
    
    
}