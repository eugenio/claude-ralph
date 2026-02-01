/**
 * Notification event types
 */
export type NotificationEvent = 'rate_limit_detected' | 'rate_limit_cleared' | 'prd_completed' | 'story_completed' | 'instance_error' | 'instance_started' | 'instance_stopped' | 'queue_empty';
/**
 * Notification channel types
 */
export type NotificationChannel = 'slack' | 'discord' | 'webhook';
/**
 * Channel configuration
 */
export interface ChannelConfig {
    type: NotificationChannel;
    url: string;
    enabled: boolean;
}
/**
 * Notification configuration
 */
export interface NotificationConfig {
    channels: Record<string, ChannelConfig>;
    events: Record<NotificationEvent, {
        enabled: boolean;
        channels: string[];
    }>;
}
/**
 * Notification payload
 */
export interface NotificationPayload {
    event: NotificationEvent;
    title: string;
    message: string;
    details?: Record<string, unknown>;
    timestamp: string;
    instanceId?: string;
    projectRoot?: string;
}
/**
 * Load notification configuration
 */
export declare function loadConfig(): Promise<NotificationConfig>;
/**
 * Save notification configuration
 */
export declare function saveConfig(config: NotificationConfig): Promise<void>;
/**
 * Add or update a notification channel
 */
export declare function addChannel(name: string, config: ChannelConfig): Promise<void>;
/**
 * Remove a notification channel
 */
export declare function removeChannel(name: string): Promise<void>;
/**
 * Subscribe a channel to an event
 */
export declare function subscribeToEvent(channelName: string, event: NotificationEvent): Promise<void>;
/**
 * Send a notification for an event
 */
export declare function notify(event: NotificationEvent, title: string, message: string, details?: Record<string, unknown>, instanceId?: string, projectRoot?: string): Promise<{
    sent: boolean;
    channels: Record<string, {
        success: boolean;
        error?: string;
    }>;
}>;
/**
 * Get notification history
 */
export declare function getHistory(limit?: number): Promise<Array<{
    payload: NotificationPayload;
    results: Record<string, {
        success: boolean;
        error?: string;
    }>;
    sentAt: string;
}>>;
/**
 * Test a notification channel
 */
export declare function testChannel(channelName: string): Promise<{
    success: boolean;
    error?: string;
}>;
//# sourceMappingURL=notifications.d.ts.map