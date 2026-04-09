import { z } from 'zod';
import { ToolDefinition, ToolHandler } from './index.js';
export declare const RalphStatusInputSchema: z.ZodObject<{
    projectRoot: z.ZodOptional<z.ZodString>;
    prdPath: z.ZodOptional<z.ZodString>;
    includeGlobal: z.ZodDefault<z.ZodBoolean>;
    includeDead: z.ZodDefault<z.ZodBoolean>;
}, "strip", z.ZodTypeAny, {
    includeGlobal: boolean;
    includeDead: boolean;
    projectRoot?: string | undefined;
    prdPath?: string | undefined;
}, {
    projectRoot?: string | undefined;
    prdPath?: string | undefined;
    includeGlobal?: boolean | undefined;
    includeDead?: boolean | undefined;
}>;
export type RalphStatusInput = z.infer<typeof RalphStatusInputSchema>;
export declare const ralphStatusDefinition: ToolDefinition;
export declare const ralphStatusHandler: ToolHandler;
//# sourceMappingURL=ralph-status.d.ts.map