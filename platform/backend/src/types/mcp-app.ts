import { z } from "zod";

/**
 * MCP App definition
 */
export const McpAppSchema = z.object({
    name: z.string(),
    title: z.string().optional(),
    description: z.string().optional(),
});

/**
 * Result of listing MCP apps
 */
export const ListAppsResultSchema = z.object({
    apps: z.array(McpAppSchema),
});

/**
 * Parameters for getting an MCP app
 */
export const GetAppRequestSchema = z.object({
    name: z.string(),
});

/**
 * Result of getting an MCP app
 */
export const GetAppResultSchema = z.object({
    url: z.string(),
});

export type McpApp = z.infer<typeof McpAppSchema>;
export type ListAppsResult = z.infer<typeof ListAppsResultSchema>;
export type GetAppRequest = z.infer<typeof GetAppRequestSchema>;
export type GetAppResult = z.infer<typeof GetAppResultSchema>;
