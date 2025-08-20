public class CraftRateTriggerHelper {
    // Method to update Project_Craft_Value_pp__c for OLIs with Billing Type 'Per Person'
    public static void updatePerPersonOLIs(Set<Id> opportunityIds) {
        // Step 1: Query to get the total craftspeople quantity by Opportunity
        AggregateResult[] craftTotals = [
            SELECT OpportunityId, SUM(Quantity) totalCraftspeople
            FROM OpportunityLineItem
            WHERE OpportunityId IN :opportunityIds
            AND Billing_Type__c = 'Hourly'  // Only count craftspeople from Hourly records
            GROUP BY OpportunityId
        ];
        
        // Create a map to store Opportunity ID to total craftspeople
        Map<Id, Decimal> oppToCraftspeopleMap = new Map<Id, Decimal>();
        
        // Populate the map
        for (AggregateResult ar : craftTotals) {
            Id oppId = (Id)ar.get('OpportunityId');
            Decimal totalCraftspeople = (Decimal)ar.get('totalCraftspeople');
            oppToCraftspeopleMap.put(oppId, totalCraftspeople);
        }
        
        // Step 2: Query for all 'Per Person' OLIs that need updating
        List<OpportunityLineItem> perPersonOLIs = [
            SELECT Id, OpportunityId, UnitPrice, Quantity, Project_Craft_Value_pp__c
            FROM OpportunityLineItem
            WHERE OpportunityId IN :opportunityIds
            AND Billing_Type__c = 'Per Person'
        ];
        
        // Step 3: Update the Project_Craft_Value_pp__c for each Per Person OLI
        List<OpportunityLineItem> olisToUpdate = new List<OpportunityLineItem>();
        
        for (OpportunityLineItem oli : perPersonOLIs) {
            // Get the total craftspeople for this OLI's opportunity
            Decimal totalCraftspeople = oppToCraftspeopleMap.get(oli.OpportunityId);
            
            // If we have craftspeople data
            if (totalCraftspeople != null && totalCraftspeople > 0) {
                // Calculate Project Craft Value PP (adjust formula as needed)
                // Example: Unit Price * Quantity * Total Craftspeople
                Decimal projectCraftValuePP = oli.UnitPrice * totalCraftspeople;
                
                // Only update if the value changed
                if (oli.Project_Craft_Value_pp__c != projectCraftValuePP) {
                    oli.Project_Craft_Value_pp__c = projectCraftValuePP;
                    olisToUpdate.add(oli);
                }
            }
        }
        
        // Update the OLIs if there are any changes
        if (!olisToUpdate.isEmpty()) {
            update olisToUpdate;
        }
    }
// Method to update Opportunity totals, including Project_Craft_Value_pp__c
    public static void updateOpportunityTotals(Set<Id> opportunityIds) {
        // First update the Project_Craft_Value_pp__c on Per Person OLIs
        updatePerPersonOLIs(opportunityIds);
        
        // Query for all OLIs related to these opportunities
        List<OpportunityLineItem> allOLIs = [
            SELECT Id, OpportunityId, Project_Craft_Value_pp__c, Project_Craft_Value__c, Billing_Type__c
            FROM OpportunityLineItem
            WHERE OpportunityId IN :opportunityIds
        ];
        // Calculate totals by Opportunity in Apex code instead of SOQL
        Map<Id, Decimal> opportunityTotals = new Map<Id, Decimal>();
        
        for (OpportunityLineItem oli : allOLIs) {
            // Initialize the total for this opportunity if not already done
            if (!opportunityTotals.containsKey(oli.OpportunityId)) {
                opportunityTotals.put(oli.OpportunityId, 0);
            }
             // Add to the running total - use Project_Craft_Value_pp__c for Per Person records, otherwise use Project_Craft_Value__c
            Decimal amountToAdd = 0;  // Initialize with a default value
if (oli.Billing_Type__c == 'Per Person') {
    amountToAdd = oli.Project_Craft_Value_pp__c;
} else if (oli.Project_Craft_Value__c != null){
    amountToAdd = oli.Project_Craft_Value__c;
} 
            
            // Add to the total (account for nulls)
            Decimal currentTotal = opportunityTotals.get(oli.OpportunityId);
            opportunityTotals.put(oli.OpportunityId, currentTotal + (amountToAdd != null ? amountToAdd : 0));
        }
         // Update Opportunities with calculated totals
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        for (Id oppId : opportunityTotals.keySet()) {
            opportunitiesToUpdate.add(new Opportunity(
                Id = oppId,
                Opportunity_Value__c = opportunityTotals.get(oppId)
            ));
        }
        
        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
    }
}