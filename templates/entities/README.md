# Knowledge Graph — Entity Storage (Layer 1)

Each entity (person, company, project) gets a folder here:

```
entities/
  alice/
    items.json    ← atomic facts (timestamped, superseding)
    summary.md    ← weekly-rewritten snapshot
  acme-corp/
    items.json
    summary.md
```

## Atomic Fact Schema (items.json)

```json
[
  {
    "id": "fact-uuid",
    "content": "Alice is the lead engineer at Acme Corp",
    "source": "conversation|meeting|transcript|manual",
    "sourceRef": "optional reference (session key, meeting id, etc)",
    "entityType": "person|company|project|organization",
    "createdAt": "2026-01-28T23:00:00Z",
    "status": "active",
    "supersedes": null,
    "edge": null
  }
]
```

### Optional Structured Edge

Facts may include an optional `edge` field for traversable relationships:

```json
{
  "id": "fact-uuid",
  "content": "Alice works at Acme Corp",
  "edge": {
    "subject": "alice",
    "predicate": "works_at",
    "object": "acme-corp"
  }
}
```

**Edge fields:**
- `subject` — entity slug (should exist in `entities/`)
- `predicate` — relationship type (snake_case)
- `object` — target entity slug

**Common predicates:**
- `works_at` / `employed_by` — employment
- `married_to` / `partner_of` — romantic relationships
- `parent_of` / `child_of` — family
- `founded` / `co_founded` — founding
- `reports_to` / `manages` — org hierarchy
- `member_of` — group membership
- `located_in` — geography

**Backwards compatibility:** The `edge` field is optional. Facts without it are valid.

### Status values:
- `active` — current fact
- `historical` — superseded by a newer fact (keeps full history)

### When facts change:
1. Add new fact with `status: "active"`
2. Set new fact's `supersedes` to the old fact's `id`
3. Set old fact's `status` to `"historical"`

Nothing is ever deleted. The knowledge graph preserves how understanding evolves.

## Summaries (summary.md)

Rewritten periodically by the synthesis pipeline. Contains a clean, current
snapshot of everything known about the entity.

## Entity Naming

Use lowercase slugs: `alice`, `acme-corp`, `project-phoenix`
