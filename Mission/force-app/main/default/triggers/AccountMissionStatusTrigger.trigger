trigger AccountMissionStatusTrigger on Account (before update, after update) {
    if (Trigger.isBefore) {
        AccountMissionStatusHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    } else {
        AccountMissionStatusHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
