import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { getGlobalPaths, ensureDir } from '../../shared/paths.js';
/**
 * Get notification config file path
 */
function getConfigPath() {
    const globalPaths = getGlobalPaths();
    return path.join(globalPaths.globalDir, 'mcp', 'notifications.json');
}
/**
 * Get notification history file path
 */
function getHistoryPath() {
    const globalPaths = getGlobalPaths();
    return path.join(globalPaths.globalDir, 'notifications', 'history.json');
}
/**
 * Default notification configuration
 */
const defaultConfig = {
    channels: {},
    events: {
        rate_limit_detected: { enabled: true, channels: [] },
        rate_limit_cleared: { enabled: true, channels: [] },
        prd_completed: { enabled: true, channels: [] },
        story_completed: { enabled: false, channels: [] },
        instance_error: { enabled: true, channels: [] },
        instance_started: { enabled: false, channels: [] },
        instance_stopped: { enabled: false, channels: [] },
        queue_empty: { enabled: false, channels: [] },
    },
};
/**
 * Load notification configuration
 */
export async function loadConfig() {
    const configPath = getConfigPath();
    try {
        const content = await fs.readFile(configPath, 'utf-8');
        const parsed = JSON.parse(content);
        return { ...defaultConfig, ...parsed };
    }
    catch {
        return defaultConfig;
    }
}
/**
 * Save notification configuration
 */
export async function saveConfig(config) {
    const configPath = getConfigPath();
    await ensureDir(path.dirname(configPath));
    await fs.writeFile(configPath, JSON.stringify(config, null, 2));
}
/**
 * Add or update a notification channel
 */
export async function addChannel(name, config) {
    const fullConfig = await loadConfig();
    fullConfig.channels[name] = config;
    await saveConfig(fullConfig);
}
/**
 * Remove a notification channel
 */
export async function removeChannel(name) {
    const fullConfig = await loadConfig();
    delete fullConfig.channels[name];
    // Remove from event subscriptions
    for (const event of Object.keys(fullConfig.events)) {
        fullConfig.events[event].channels = fullConfig.events[event].channels
            .filter(c => c !== name);
    }
    await saveConfig(fullConfig);
}
/**
 * Subscribe a channel to an event
 */
export async function subscribeToEvent(channelName, event) {
    const config = await loadConfig();
    if (!config.channels[channelName]) {
        throw new Error(`Channel not found: ${channelName}`);
    }
    if (!config.events[event].channels.includes(channelName)) {
        config.events[event].channels.push(channelName);
    }
    config.events[event].enabled = true;
    await saveConfig(config);
}
/**
 * Format payload for Slack
 */
function formatSlackPayload(payload) {
    const color = getEventColor(payload.event);
    const emoji = getEventEmoji(payload.event);
    return {
        attachments: [{
                color,
                blocks: [
                    {
                        type: 'header',
                        text: {
                            type: 'plain_text',
                            text: `${emoji} ${payload.title}`,
                            emoji: true,
                        },
                    },
                    {
                        type: 'section',
                        text: {
                            type: 'mrkdwn',
                            text: payload.message,
                        },
                    },
                    ...(payload.details ? [{
                            type: 'section',
                            fields: Object.entries(payload.details).map(([key, value]) => ({
                                type: 'mrkdwn',
                                text: `*${key}:*\n${value}`,
                            })),
                        }] : []),
                    {
                        type: 'context',
                        elements: [
                            {
                                type: 'mrkdwn',
                                text: `Ralph MCP | ${payload.timestamp}`,
                            },
                        ],
                    },
                ],
            }],
    };
}
/**
 * Format payload for Discord
 */
function formatDiscordPayload(payload) {
    const color = getEventColorDecimal(payload.event);
    const emoji = getEventEmoji(payload.event);
    return {
        embeds: [{
                title: `${emoji} ${payload.title}`,
                description: payload.message,
                color,
                fields: payload.details
                    ? Object.entries(payload.details).map(([name, value]) => ({
                        name,
                        value: String(value),
                        inline: true,
                    }))
                    : [],
                footer: {
                    text: 'Ralph MCP',
                },
                timestamp: payload.timestamp,
            }],
    };
}
/**
 * Format payload for generic webhook
 */
function formatWebhookPayload(payload) {
    return payload;
}
/**
 * Get color for event (hex)
 */
function getEventColor(event) {
    switch (event) {
        case 'rate_limit_detected':
            return '#ff9800'; // Orange
        case 'rate_limit_cleared':
            return '#4caf50'; // Green
        case 'prd_completed':
            return '#2196f3'; // Blue
        case 'story_completed':
            return '#8bc34a'; // Light green
        case 'instance_error':
            return '#f44336'; // Red
        case 'instance_started':
            return '#9c27b0'; // Purple
        case 'instance_stopped':
            return '#607d8b'; // Gray
        case 'queue_empty':
            return '#00bcd4'; // Cyan
        default:
            return '#757575'; // Default gray
    }
}
/**
 * Get color for event (decimal for Discord)
 */
function getEventColorDecimal(event) {
    const hex = getEventColor(event).replace('#', '');
    return parseInt(hex, 16);
}
/**
 * Get emoji for event
 */
function getEventEmoji(event) {
    switch (event) {
        case 'rate_limit_detected':
            return '⚠️';
        case 'rate_limit_cleared':
            return '✅';
        case 'prd_completed':
            return '🎉';
        case 'story_completed':
            return '📝';
        case 'instance_error':
            return '❌';
        case 'instance_started':
            return '🚀';
        case 'instance_stopped':
            return '🛑';
        case 'queue_empty':
            return '📭';
        default:
            return '📢';
    }
}
/**
 * Send notification to a specific channel
 */
async function sendToChannel(channel, payload) {
    if (!channel.enabled) {
        return { success: true };
    }
    let body;
    switch (channel.type) {
        case 'slack':
            body = formatSlackPayload(payload);
            break;
        case 'discord':
            body = formatDiscordPayload(payload);
            break;
        case 'webhook':
        default:
            body = formatWebhookPayload(payload);
            break;
    }
    try {
        const response = await fetch(channel.url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(body),
        });
        if (!response.ok) {
            return {
                success: false,
                error: `HTTP ${response.status}: ${response.statusText}`,
            };
        }
        return { success: true };
    }
    catch (error) {
        return {
            success: false,
            error: error instanceof Error ? error.message : String(error),
        };
    }
}
/**
 * Log notification to history
 */
async function logNotification(payload, results) {
    const historyPath = getHistoryPath();
    await ensureDir(path.dirname(historyPath));
    let history = [];
    try {
        const content = await fs.readFile(historyPath, 'utf-8');
        history = JSON.parse(content);
    }
    catch {
        // File doesn't exist or is invalid
    }
    history.push({
        payload,
        results,
        sentAt: new Date().toISOString(),
    });
    // Keep last 1000 entries
    if (history.length > 1000) {
        history = history.slice(-1000);
    }
    await fs.writeFile(historyPath, JSON.stringify(history, null, 2));
}
/**
 * Send a notification for an event
 */
export async function notify(event, title, message, details, instanceId, projectRoot) {
    const config = await loadConfig();
    const eventConfig = config.events[event];
    if (!eventConfig?.enabled || eventConfig.channels.length === 0) {
        return { sent: false, channels: {} };
    }
    const payload = {
        event,
        title,
        message,
        details,
        timestamp: new Date().toISOString(),
        instanceId,
        projectRoot,
    };
    const results = {};
    for (const channelName of eventConfig.channels) {
        const channel = config.channels[channelName];
        if (channel) {
            results[channelName] = await sendToChannel(channel, payload);
        }
    }
    await logNotification(payload, results);
    return {
        sent: true,
        channels: results,
    };
}
/**
 * Get notification history
 */
export async function getHistory(limit = 50) {
    const historyPath = getHistoryPath();
    try {
        const content = await fs.readFile(historyPath, 'utf-8');
        const history = JSON.parse(content);
        return history.slice(-limit);
    }
    catch {
        return [];
    }
}
/**
 * Test a notification channel
 */
export async function testChannel(channelName) {
    const config = await loadConfig();
    const channel = config.channels[channelName];
    if (!channel) {
        return { success: false, error: `Channel not found: ${channelName}` };
    }
    const payload = {
        event: 'instance_started',
        title: 'Test Notification',
        message: 'This is a test notification from Ralph MCP.',
        timestamp: new Date().toISOString(),
    };
    return sendToChannel(channel, payload);
}
//# sourceMappingURL=notifications.js.map