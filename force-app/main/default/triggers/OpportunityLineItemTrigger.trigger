trigger OpportunityLineItemTrigger on OpportunityLineItem (after insert, after update, after delete, after undelete) {
    // Create a set to hold unique Opportunity IDs that need updates
    Set<Id> opportunityIdsToUpdate = new Set<Id>();
    
    // When Craft Rates are inserted, updated, or undeleted
    if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
        for (OpportunityLineItem oli : Trigger.new) {
            opportunityIdsToUpdate.add(oli.OpportunityId);
        }
    }
    
    // When Craft Rates are deleted
    if (Trigger.isDelete) {
        for (OpportunityLineItem oli : Trigger.old) {
            opportunityIdsToUpdate.add(oli.OpportunityId);
        }
    }
    
    // If we have Opportunities to update
    if (!opportunityIdsToUpdate.isEmpty()) {
        // Call helper method to update Opportunities
        CraftRateTriggerHelper.updateOpportunityTotals(opportunityIdsToUpdate);
    }
}