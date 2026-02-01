import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { randomBytes } from 'node:crypto';
import {
  Queue,
  QueueSchema,
  QueueEntry,
  QueueEntryStatus,
  QueueSummary,
  recordQueueDepth,
} from '../../shared/index.js';
import { getGlobalPaths, ensureDir } from '../../shared/paths.js';

/**
 * Get the queue file path
 */
function getQueueFile(): string {
  const globalPaths = getGlobalPaths();
  return path.join(globalPaths.globalDir, 'queue.json');
}

/**
 * Read the queue file
 */
async function readQueue(): Promise<Queue> {
  const queueFile = getQueueFile();

  try {
    const content = await fs.readFile(queueFile, 'utf-8');
    const parsed = JSON.parse(content);
    return QueueSchema.parse(parsed);
  } catch {
    return { entries: [] };
  }
}

/**
 * Write the queue file atomically
 */
async function writeQueue(queue: Queue): Promise<void> {
  const queueFile = getQueueFile();
  const tempFile = `${queueFile}.tmp`;

  await ensureDir(path.dirname(queueFile));
  await fs.writeFile(tempFile, JSON.stringify(queue, null, 2));
  await fs.rename(tempFile, queueFile);
}

/**
 * Generate a unique queue entry ID
 */
function generateEntryId(): string {
  const timestamp = Math.floor(Date.now() / 1000);
  const random = randomBytes(4).toString('hex');
  return `q-${timestamp}-${random}`;
}

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
export async function addQueueEntry(
  options: AddQueueEntryOptions
): Promise<AddQueueEntryResult> {
  const { prdPath, projectRoot, priority = 10 } = options;

  // Validate paths exist
  try {
    await fs.access(prdPath);
  } catch {
    return {
      success: false,
      error: `PRD file not found: ${prdPath}`,
    };
  }

  try {
    await fs.access(projectRoot);
  } catch {
    return {
      success: false,
      error: `Project root not found: ${projectRoot}`,
    };
  }

  const queue = await readQueue();

  // Check for duplicate
  const existing = queue.entries.find(
    e => e.prdPath === prdPath && e.projectRoot === projectRoot && e.status === 'pending'
  );

  if (existing) {
    return {
      success: false,
      error: `Entry already exists in queue: ${existing.id}`,
    };
  }

  const entryId = generateEntryId();
  const entry: QueueEntry = {
    id: entryId,
    prdPath,
    projectRoot,
    priority,
    status: 'pending',
    addedAt: new Date().toISOString(),
    claimedBy: null,
    claimedAt: null,
    completedAt: null,
  };

  queue.entries.push(entry);
  await writeQueue(queue);

  // Record queue depth metric
  recordQueueDepth(queue.entries.length, 'pending');

  return {
    success: true,
    entryId,
  };
}

export interface ListQueueEntriesOptions {
  status?: QueueEntryStatus | 'all';
}

/**
 * List queue entries with optional filtering
 */
export async function listQueueEntries(
  options: ListQueueEntriesOptions = {}
): Promise<QueueEntry[]> {
  const { status = 'all' } = options;
  const queue = await readQueue();

  if (status === 'all') {
    return queue.entries;
  }

  return queue.entries.filter(e => e.status === status);
}

/**
 * Get queue summary
 */
export async function getQueueSummary(): Promise<QueueSummary> {
  const queue = await readQueue();

  const summary: QueueSummary = {
    total: queue.entries.length,
    pending: 0,
    active: 0,
    completed: 0,
    failed: 0,
  };

  for (const entry of queue.entries) {
    switch (entry.status) {
      case 'pending':
        summary.pending++;
        break;
      case 'active':
        summary.active++;
        break;
      case 'completed':
        summary.completed++;
        break;
      case 'failed':
        summary.failed++;
        break;
    }
  }

  return summary;
}

/**
 * Remove a queue entry by ID
 */
export async function removeQueueEntry(
  entryId: string
): Promise<{ success: boolean; error?: string }> {
  const queue = await readQueue();

  const index = queue.entries.findIndex(e => e.id === entryId);

  if (index === -1) {
    return {
      success: false,
      error: `Entry not found: ${entryId}`,
    };
  }

  queue.entries.splice(index, 1);
  await writeQueue(queue);

  return { success: true };
}

/**
 * Update a queue entry status
 */
export async function updateQueueEntryStatus(
  entryId: string,
  status: QueueEntryStatus,
  claimedBy?: string
): Promise<{ success: boolean; error?: string }> {
  const queue = await readQueue();

  const entry = queue.entries.find(e => e.id === entryId);

  if (!entry) {
    return {
      success: false,
      error: `Entry not found: ${entryId}`,
    };
  }

  entry.status = status;

  if (status === 'active' && claimedBy) {
    entry.claimedBy = claimedBy;
    entry.claimedAt = new Date().toISOString();
  }

  if (status === 'completed' || status === 'failed') {
    entry.completedAt = new Date().toISOString();
  }

  await writeQueue(queue);

  return { success: true };
}

/**
 * Clear completed entries from the queue
 */
export async function clearCompletedEntries(): Promise<number> {
  const queue = await readQueue();
  const originalCount = queue.entries.length;

  queue.entries = queue.entries.filter(
    e => e.status !== 'completed' && e.status !== 'failed'
  );

  await writeQueue(queue);

  return originalCount - queue.entries.length;
}
