import { QueueEntry, QueueEntryStatus, QueueSummary } from '../../shared/index.js';
export interface AddQueueEntryOptions {
    prdPath: string;
    projectRoot: string;
    priority?: number;
}
export interface AddQueueEntryResult {
    success: boolean;
    entryId?: string;
    error?: string;
}
/**
 * Add a PRD to the queue
 */
export declare function addQueueEntry(options: AddQueueEntryOptions): Promise<AddQueueEntryResult>;
export interface ListQueueEntriesOptions {
    status?: QueueEntryStatus | 'all';
}
/**
 * List queue entries with optional filtering
 */
export declare function listQueueEntries(options?: ListQueueEntriesOptions): Promise<QueueEntry[]>;
/**
 * Get queue summary
 */
export declare function getQueueSummary(): Promise<QueueSummary>;
/**
 * Remove a queue entry by ID
 */
export declare function removeQueueEntry(entryId: string): Promise<{
    success: boolean;
    error?: string;
}>;
/**
 * Update a queue entry status
 */
export declare function updateQueueEntryStatus(entryId: string, status: QueueEntryStatus, claimedBy?: string): Promise<{
    success: boolean;
    error?: string;
}>;
/**
 * Clear completed entries from the queue
 */
export declare function clearCompletedEntries(): Promise<number>;
//# sourceMappingURL=queue-manager.d.ts.map