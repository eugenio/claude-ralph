import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { getAllInstances } from './state-reader.js';
/**
 * Request an instance to pause after current iteration
 */
export async function pauseInstance(instanceId) {
    const instances = await getAllInstances({
        includeGlobal: true,
        includeDead: false,
    });
    const instance = instances.find(i => i.instanceId === instanceId);
    if (!instance) {
        return {
            instanceId,
            success: false,
            error: `Instance not found: ${instanceId}`,
        };
    }
    return pauseInstanceByInfo(instance);
}
/**
 * Pause an instance by its info
 */
async function pauseInstanceByInfo(instance) {
    // Check if already paused
    if (instance.state === 'paused') {
        return {
            instanceId: instance.instanceId,
            success: true,
            previousState: 'paused',
        };
    }
    // Check if in a state that can be paused
    const pausableStates = ['idle', 'waiting', 'claiming', 'working', 'merging'];
    if (!pausableStates.includes(instance.state)) {
        return {
            instanceId: instance.instanceId,
            success: false,
            error: `Cannot pause instance in state: ${instance.state}`,
        };
    }
    // Create pause request file
    const pauseFile = path.join(instance.instanceDir, '.pause_requested');
    try {
        const pauseData = {
            requestedAt: new Date().toISOString(),
            requestedAtEpoch: Math.floor(Date.now() / 1000),
            previousState: instance.state,
        };
        await fs.writeFile(pauseFile, JSON.stringify(pauseData, null, 2));
        return {
            instanceId: instance.instanceId,
            success: true,
            previousState: instance.state,
        };
    }
    catch (error) {
        return {
            instanceId: instance.instanceId,
            success: false,
            error: error instanceof Error ? error.message : String(error),
        };
    }
}
/**
 * Resume a paused instance
 */
export async function resumeInstance(instanceId) {
    const instances = await getAllInstances({
        includeGlobal: true,
        includeDead: false,
    });
    const instance = instances.find(i => i.instanceId === instanceId);
    if (!instance) {
        return {
            instanceId,
            success: false,
            error: `Instance not found: ${instanceId}`,
        };
    }
    return resumeInstanceByInfo(instance);
}
/**
 * Resume an instance by its info
 */
async function resumeInstanceByInfo(instance) {
    // Check if instance is paused or rate_limited
    const resumableStates = ['paused', 'rate_limited'];
    if (!resumableStates.includes(instance.state)) {
        // Check if there's a pending pause request to cancel
        const pauseFile = path.join(instance.instanceDir, '.pause_requested');
        try {
            await fs.access(pauseFile);
            await fs.unlink(pauseFile);
            return {
                instanceId: instance.instanceId,
                success: true,
            };
        }
        catch {
            return {
                instanceId: instance.instanceId,
                success: false,
                error: `Instance is not paused (current state: ${instance.state})`,
            };
        }
    }
    // Remove pause request file if it exists
    const pauseFile = path.join(instance.instanceDir, '.pause_requested');
    try {
        await fs.unlink(pauseFile);
    }
    catch {
        // File might not exist
    }
    // Create resume signal file
    const resumeFile = path.join(instance.instanceDir, '.resume_requested');
    try {
        const resumeData = {
            requestedAt: new Date().toISOString(),
            requestedAtEpoch: Math.floor(Date.now() / 1000),
        };
        await fs.writeFile(resumeFile, JSON.stringify(resumeData, null, 2));
        return {
            instanceId: instance.instanceId,
            success: true,
        };
    }
    catch (error) {
        return {
            instanceId: instance.instanceId,
            success: false,
            error: error instanceof Error ? error.message : String(error),
        };
    }
}
/**
 * Check if an instance has a pending pause request
 */
export async function hasPauseRequest(instanceDir) {
    const pauseFile = path.join(instanceDir, '.pause_requested');
    try {
        await fs.access(pauseFile);
        return true;
    }
    catch {
        return false;
    }
}
/**
 * Check if an instance has a pending resume request
 */
export async function hasResumeRequest(instanceDir) {
    const resumeFile = path.join(instanceDir, '.resume_requested');
    try {
        await fs.access(resumeFile);
        return true;
    }
    catch {
        return false;
    }
}
/**
 * Get pause request details
 */
export async function getPauseRequest(instanceDir) {
    const pauseFile = path.join(instanceDir, '.pause_requested');
    try {
        const content = await fs.readFile(pauseFile, 'utf-8');
        return JSON.parse(content);
    }
    catch {
        return null;
    }
}
//# sourceMappingURL=pause-manager.js.map