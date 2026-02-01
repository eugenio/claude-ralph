import { z } from 'zod';
import { ToolDefinition, ToolHandler } from './index.js';
export declare const RalphStartInputSchema: z.ZodObject<{
    prdPath: z.ZodString;
    projectRoot: z.ZodString;
    maxIterations: z.ZodDefault<z.ZodNumber>;
    count: z.ZodDefault<z.ZodNumber>;
    queueMode: z.ZodDefault<z.ZodBoolean>;
}, "strip", z.ZodTypeAny, {
    maxIterations: number;
    projectRoot: string;
    prdPath: string;
    queueMode: boolean;
    count: number;
}, {
    projectRoot: string;
    prdPath: string;
    maxIterations?: number | undefined;
    queueMode?: boolean | undefined;
    count?: number | undefined;
}>;
export type RalphStartInput = z.infer<typeof RalphStartInputSchema>;
export declare const ralphStartDefinition: ToolDefinition;
export declare const ralphStartHandler: ToolHandler;
//# sourceMappingURL=ralph-start.d.ts.map