-- Migrate proxy-sniffed tools from per-agent (agent_id set) to shared (agent_id=NULL).
-- Proxy tools: agent_id IS NOT NULL AND catalog_id IS NULL AND delegate_to_agent_id IS NULL.
-- After migration, proxy tools become shared like MCP tools: agent_id=NULL, linked via agent_tools.

-- Step 0: Delete proxy-sniffed tools that were discovered by agents (agent_type != 'profile' and != 'llm_proxy').
-- These are stale duplicates from internal agents that should not be shared.
-- First remove their agent_tools entries, then delete the tool rows.
DELETE FROM agent_tools
WHERE tool_id IN (
  SELECT t.id FROM tools t
  JOIN agents a ON a.id = t.agent_id
  WHERE t.agent_id IS NOT NULL
    AND t.catalog_id IS NULL
    AND t.delegate_to_agent_id IS NULL
    AND a.agent_type NOT IN ('profile', 'llm_proxy')
);
--> statement-breakpoint

DELETE FROM tools
WHERE id IN (
  SELECT t.id FROM tools t
  JOIN agents a ON a.id = t.agent_id
  WHERE t.agent_id IS NOT NULL
    AND t.catalog_id IS NULL
    AND t.delegate_to_agent_id IS NULL
    AND a.agent_type NOT IN ('profile', 'llm_proxy')
);
--> statement-breakpoint

-- Step 1: For each proxy tool name, identify the "survivor" (oldest by created_at).
-- Transfer agent_tools entries from duplicate tools to the survivor.
-- Use a CTE to find duplicates and re-point their agent_tools.

-- Create a temp table with survivor tool IDs (one per name)
CREATE TEMP TABLE proxy_tool_survivors AS
SELECT DISTINCT ON (name) id AS survivor_id, name, agent_id AS original_agent_id
FROM tools
WHERE agent_id IS NOT NULL AND catalog_id IS NULL AND delegate_to_agent_id IS NULL
ORDER BY name, created_at ASC;
--> statement-breakpoint

-- Step 2: Ensure survivors have agent_tools entries for their original agent_id
INSERT INTO agent_tools (id, agent_id, tool_id, created_at, updated_at)
SELECT gen_random_uuid(), s.original_agent_id, s.survivor_id, NOW(), NOW()
FROM proxy_tool_survivors s
WHERE NOT EXISTS (
  SELECT 1 FROM agent_tools at
  WHERE at.agent_id = s.original_agent_id AND at.tool_id = s.survivor_id
);
--> statement-breakpoint

-- Step 3: For non-survivor tools, ensure their agent has an agent_tools entry pointing to the survivor
INSERT INTO agent_tools (id, agent_id, tool_id, created_at, updated_at)
SELECT gen_random_uuid(), t.agent_id, s.survivor_id, NOW(), NOW()
FROM tools t
JOIN proxy_tool_survivors s ON s.name = t.name
WHERE t.agent_id IS NOT NULL
  AND t.catalog_id IS NULL
  AND t.delegate_to_agent_id IS NULL
  AND t.id != s.survivor_id
  AND NOT EXISTS (
    SELECT 1 FROM agent_tools at
    WHERE at.agent_id = t.agent_id AND at.tool_id = s.survivor_id
  );
--> statement-breakpoint

-- Step 4: Re-point any agent_tools entries that reference non-survivor tools to the survivor.
-- First, for entries where the (agent_id, survivor_tool_id) combo already exists, just delete the old one.
DELETE FROM agent_tools
WHERE tool_id IN (
  SELECT t.id FROM tools t
  JOIN proxy_tool_survivors s ON s.name = t.name
  WHERE t.agent_id IS NOT NULL
    AND t.catalog_id IS NULL
    AND t.delegate_to_agent_id IS NULL
    AND t.id != s.survivor_id
);
--> statement-breakpoint

-- Step 5: Delete duplicate (non-survivor) tool rows. Policies cascade delete.
DELETE FROM tools
WHERE agent_id IS NOT NULL
  AND catalog_id IS NULL
  AND delegate_to_agent_id IS NULL
  AND id NOT IN (SELECT survivor_id FROM proxy_tool_survivors);
--> statement-breakpoint

-- Step 6: Set agent_id = NULL on all surviving proxy tools (make them shared)
UPDATE tools
SET agent_id = NULL
WHERE agent_id IS NOT NULL
  AND catalog_id IS NULL
  AND delegate_to_agent_id IS NULL;
--> statement-breakpoint

-- Cleanup temp table
DROP TABLE proxy_tool_survivors;
--> statement-breakpoint

-- Step 6b: Merge proxy-vs-catalog duplicates.
-- After Step 6, some shared proxy tools (agent_id=NULL, catalog_id=NULL) may have the same name
-- as a catalog tool (catalog_id IS NOT NULL). Keep the catalog tool and transfer assignments + policies.

-- Transfer agent_tools assignments from proxy tool to catalog tool (skip if already assigned)
INSERT INTO agent_tools (id, agent_id, tool_id, created_at, updated_at)
SELECT gen_random_uuid(), proxy_at.agent_id, catalog_t.id, NOW(), NOW()
FROM agent_tools proxy_at
JOIN tools proxy_t ON proxy_t.id = proxy_at.tool_id
JOIN tools catalog_t ON catalog_t.name = proxy_t.name AND catalog_t.catalog_id IS NOT NULL
WHERE proxy_t.agent_id IS NULL
  AND proxy_t.catalog_id IS NULL
  AND proxy_t.delegate_to_agent_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM agent_tools existing
    WHERE existing.agent_id = proxy_at.agent_id AND existing.tool_id = catalog_t.id
  );
--> statement-breakpoint

-- Proxy policies will be cascade-deleted when the proxy tool rows are removed below.
-- The catalog tool's policies are the authoritative ones and are kept as-is.

-- Delete agent_tools for the proxy duplicates (any remaining)
DELETE FROM agent_tools
WHERE tool_id IN (
  SELECT proxy_t.id
  FROM tools proxy_t
  JOIN tools catalog_t ON catalog_t.name = proxy_t.name AND catalog_t.catalog_id IS NOT NULL
  WHERE proxy_t.agent_id IS NULL
    AND proxy_t.catalog_id IS NULL
    AND proxy_t.delegate_to_agent_id IS NULL
);
--> statement-breakpoint

-- Delete the proxy tool rows that have catalog equivalents
DELETE FROM tools
WHERE id IN (
  SELECT proxy_t.id
  FROM tools proxy_t
  JOIN tools catalog_t ON catalog_t.name = proxy_t.name AND catalog_t.catalog_id IS NOT NULL
  WHERE proxy_t.agent_id IS NULL
    AND proxy_t.catalog_id IS NULL
    AND proxy_t.delegate_to_agent_id IS NULL
);
