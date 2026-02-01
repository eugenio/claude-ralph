import { z } from 'zod';
import { ToolDefinition, ToolHandler } from './index.js';
export declare const RalphStopInputSchema: z.ZodObject<{
    instanceId: z.ZodOptional<z.ZodString>;
    force: z.ZodDefault<z.ZodBoolean>;
    projectRoot: z.ZodOptional<z.ZodString>;
}, "strip", z.ZodTypeAny, {
    force: boolean;
    instanceId?: string | undefined;
    projectRoot?: string | undefined;
}, {
    instanceId?: string | undefined;
    projectRoot?: string | undefined;
    force?: boolean | undefined;
}>;
export type RalphStopInput = z.infer<typeof RalphStopInputSchema>;
export declare const ralphStopDefinition: ToolDefinition;
export declare const ralphStopHandler: ToolHandler;
//# sourceMappingURL=ralph-stop.d.ts.map