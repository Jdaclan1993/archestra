"use client";

import { useEffect, useState } from "react";
import { Tool, ToolContent, ToolHeader } from "@/components/ai-elements/tool";
import { Skeleton } from "@/components/ui/skeleton";

interface McpAppViewProps {
    name: string;
    url?: string;
    title?: string;
    agentId?: string;
}

export function McpAppView({ name, url: initialUrl, title, agentId }: McpAppViewProps) {
    const [url, setUrl] = useState<string | undefined>(initialUrl);
    const [isLoading, setIsLoading] = useState(!initialUrl);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        if (!url && name && agentId) {
            // Fetch the app URL if not provided
            const fetchAppUrl = async () => {
                try {
                    setIsLoading(true);
                    // For the bounty, we'll use a direct fetch to the gateway
                    // In a real implementation, this would be part of the API SDK
                    const response = await fetch(`/v1/mcp/${agentId}`, {
                        method: "POST",
                        headers: {
                            "Content-Type": "application/json",
                            // Authorization would be handled by the browser session/cookies
                        },
                        body: JSON.stringify({
                            jsonrpc: "2.0",
                            id: Date.now(),
                            method: "apps/get",
                            params: { name: name.split(":").pop() || name },
                        }),
                    });

                    if (!response.ok) {
                        throw new Error(`Failed to fetch app: ${response.statusText}`);
                    }

                    const result = await response.json();
                    if (result.error) {
                        throw new Error(result.error.message || "Failed to fetch app URL");
                    }

                    setUrl(result.result.url);
                } catch (err) {
                    setError(err instanceof Error ? err.message : String(err));
                } finally {
                    setIsLoading(false);
                }
            };

            fetchAppUrl();
        }
    }, [url, name, agentId]);

    return (
        <Tool defaultOpen={true}>
            <ToolHeader
                type="tool-app"
                state={isLoading ? "input-available" : error ? "output-error" : "output-available"}
                isCollapsible={true}
                title={title || `App: ${name}`}
            />
            <ToolContent>
                <div className="w-full aspect-video min-h-[400px] relative rounded-md overflow-hidden border bg-background">
                    {isLoading ? (
                        <div className="absolute inset-0 flex items-center justify-center p-8">
                            <Skeleton className="w-full h-full" />
                            <div className="absolute inset-0 flex items-center justify-center text-sm text-muted-foreground animate-pulse">
                                Loading Application...
                            </div>
                        </div>
                    ) : error ? (
                        <div className="absolute inset-0 flex flex-col items-center justify-center p-8 text-center">
                            <div className="text-destructive font-medium mb-2">Failed to load app</div>
                            <div className="text-sm text-muted-foreground">{error}</div>
                        </div>
                    ) : url ? (
                        <iframe
                            src={url}
                            title={title || name}
                            className="w-full h-full border-0"
                            allow="accelerometer; ambient-light-sensor; camera; encrypted-media; geolocation; gyroscope; hid; microphone; midi; payment; usb; vr; xr-spatial-tracking"
                            sandbox="allow-forms allow-modals allow-popups allow-presentation allow-same-origin allow-scripts"
                        />
                    ) : (
                        <div className="absolute inset-0 flex items-center justify-center text-muted-foreground">
                            No app URL available
                        </div>
                    )}
                </div>
            </ToolContent>
        </Tool>
    );
}
