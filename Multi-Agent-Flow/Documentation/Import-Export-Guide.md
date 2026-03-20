# Multi-Agent-Flow Import/Export Guide

## Export Format

### JSON Structure

```json
{
  "project": {
    "id": "uuid",
    "name": "Project Name",
    "agents": [...],
    "workflows": [...],
    "permissions": [...],
    "createdAt": "ISO8601 date",
    "updatedAt": "ISO8601 date"
  },
  "tasks": [...],
  "messages": [...],
  "executionResults": [...],
  "kanban": {
    "tasks": {
      "To Do": [...],
      "In Progress": [...],
      "Done": [...],
      "Blocked": [...]
    }
  },
  "exportedAt": 1234567890,
  "version": "1.0",
  "format": "maoproject"
}
```

### Export Options

| Option | Description |
|--------|-------------|
| Include Tasks | Export all tasks |
| Include Kanban Status | Export task status by column |
| Include Messages | Export chat messages |
| Include Execution Results | Export execution history |

### Supported Formats

- **JSON** (.json) - Full data export
- **YAML** (.yaml) - Human-readable format
- **Markdown** (.md) - Documentation format

## Import Guide

### Step 1: Select File

1. Click "Import Project..."
2. Select a `.json` file
3. System validates file format

### Step 2: Preview

Review imported data:
- Project information
- Data statistics
- Warnings about potential issues

### Step 3: Confirm

Select data to import:
- Project configuration
- Tasks & Kanban
- Messages
- Execution results

### Data Validation

The system validates:
- JSON structure
- Required fields
- Data compatibility
- Version compatibility

### Error Handling

If import fails:
1. System shows error message
2. Original data is preserved
3. You can retry with corrected file

## Backup & Restore

### Create Backup

1. Click "Create Backup..."
2. Choose location
3. Backup includes all project data

### Restore from Backup

1. Click "Restore from Backup..."
2. Select backup file
3. Confirm restoration

## Templates

Save current project as template:
1. Click "Save as Template..."
2. Enter template name
3. Template saved for future use
