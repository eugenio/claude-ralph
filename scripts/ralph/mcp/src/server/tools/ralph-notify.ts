import { ToolDefinition, ToolHandler, jsonResponse, errorResponse } from './index.js';
import {
  notify,
  addChannel,
  removeChannel,
  subscribeToEvent,
  loadConfig,
  testChannel,
  getHistory,
  NotificationEvent,
  NotificationChannel,
} from '../../client/services/notifications.js';

// ralph_notify - Send a notification
export const ralphNotifyDefinition: ToolDefinition = {
  name: 'ralph_notify',
  description: 'Send a notification to configured channels',
  inputSchema: {
    type: 'object',
    properties: {
      event: {
        type: 'string',
        enum: [
          'rate_limit_detected',
          'rate_limit_cleared',
          'prd_completed',
          'story_completed',
          'instance_error',
          'instance_started',
          'instance_stopped',
          'queue_empty',
        ],
        description: 'Event type',
      },
      title: {
        type: 'string',
        description: 'Notification title',
      },
      message: {
        type: 'string',
        description: 'Notification message',
      },
      details: {
        type: 'object',
        description: 'Additional details (key-value pairs)',
      },
      instanceId: {
        type: 'string',
        description: 'Instance ID (optional)',
      },
      projectRoot: {
        type: 'string',
        description: 'Project root (optional)',
      },
    },
    required: ['event', 'title', 'message'],
  },
};

export const ralphNotifyHandler: ToolHandler = async (args) => {
  const event = args.event as NotificationEvent;
  const title = args.title as string;
  const message = args.message as string;
  const details = args.details as Record<string, unknown> | undefined;
  const instanceId = args.instanceId as string | undefined;
  const projectRoot = args.projectRoot as string | undefined;

  const result = await notify(event, title, message, details, instanceId, projectRoot);

  if (!result.sent) {
    return jsonResponse({
      sent: false,
      message: 'No channels configured for this event',
    });
  }

  const failures = Object.entries(result.channels)
    .filter(([, r]) => !r.success)
    .map(([name, r]) => `${name}: ${r.error}`);

  if (failures.length > 0) {
    return jsonResponse({
      sent: true,
      partialFailure: true,
      failures,
      message: `Notification sent with ${failures.length} failures`,
    });
  }

  return jsonResponse({
    sent: true,
    channels: Object.keys(result.channels),
    message: 'Notification sent successfully',
  });
};

// ralph_notify_config - Manage notification configuration
export const ralphNotifyConfigDefinition: ToolDefinition = {
  name: 'ralph_notify_config',
  description: 'Manage notification channels and subscriptions',
  inputSchema: {
    type: 'object',
    properties: {
      action: {
        type: 'string',
        enum: ['list', 'add_channel', 'remove_channel', 'subscribe', 'test'],
        description: 'Action to perform',
      },
      channelName: {
        type: 'string',
        description: 'Channel name (for add/remove/subscribe/test)',
      },
      channelType: {
        type: 'string',
        enum: ['slack', 'discord', 'webhook'],
        description: 'Channel type (for add_channel)',
      },
      channelUrl: {
        type: 'string',
        description: 'Webhook URL (for add_channel)',
      },
      event: {
        type: 'string',
        enum: [
          'rate_limit_detected',
          'rate_limit_cleared',
          'prd_completed',
          'story_completed',
          'instance_error',
          'instance_started',
          'instance_stopped',
          'queue_empty',
        ],
        description: 'Event to subscribe to (for subscribe)',
      },
    },
    required: ['action'],
  },
};

export const ralphNotifyConfigHandler: ToolHandler = async (args) => {
  const action = args.action as string;

  switch (action) {
    case 'list': {
      const config = await loadConfig();
      return jsonResponse({
        channels: config.channels,
        events: config.events,
      });
    }

    case 'add_channel': {
      const name = args.channelName as string;
      const type = args.channelType as NotificationChannel;
      const url = args.channelUrl as string;

      if (!name || !type || !url) {
        return errorResponse('channelName, channelType, and channelUrl are required');
      }

      await addChannel(name, { type, url, enabled: true });
      return jsonResponse({
        success: true,
        message: `Channel "${name}" added successfully`,
      });
    }

    case 'remove_channel': {
      const name = args.channelName as string;
      if (!name) {
        return errorResponse('channelName is required');
      }

      await removeChannel(name);
      return jsonResponse({
        success: true,
        message: `Channel "${name}" removed`,
      });
    }

    case 'subscribe': {
      const channelName = args.channelName as string;
      const event = args.event as NotificationEvent;

      if (!channelName || !event) {
        return errorResponse('channelName and event are required');
      }

      try {
        await subscribeToEvent(channelName, event);
        return jsonResponse({
          success: true,
          message: `Channel "${channelName}" subscribed to "${event}"`,
        });
      } catch (error) {
        return errorResponse(error instanceof Error ? error.message : String(error));
      }
    }

    case 'test': {
      const channelName = args.channelName as string;
      if (!channelName) {
        return errorResponse('channelName is required');
      }

      const result = await testChannel(channelName);
      if (result.success) {
        return jsonResponse({
          success: true,
          message: `Test notification sent to "${channelName}"`,
        });
      } else {
        return errorResponse(`Test failed: ${result.error}`);
      }
    }

    default:
      return errorResponse(`Unknown action: ${action}`);
  }
};

// ralph_notify_history - Get notification history
export const ralphNotifyHistoryDefinition: ToolDefinition = {
  name: 'ralph_notify_history',
  description: 'Get recent notification history',
  inputSchema: {
    type: 'object',
    properties: {
      limit: {
        type: 'number',
        description: 'Number of entries to return (default: 50)',
      },
    },
  },
};

export const ralphNotifyHistoryHandler: ToolHandler = async (args) => {
  const limit = (args.limit as number) || 50;
  const history = await getHistory(limit);

  return jsonResponse({
    count: history.length,
    entries: history,
  });
};
