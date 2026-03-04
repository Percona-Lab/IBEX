#!/usr/bin/env node

import { createMCPServer } from './shared.js';
import { ServiceNowConnector } from '../connectors/servicenow.js';

const snow = new ServiceNowConnector(
  process.env.SERVICENOW_INSTANCE,
  process.env.SERVICENOW_USERNAME,
  process.env.SERVICENOW_PASSWORD
);

await createMCPServer({
  name: 'ibex-servicenow',
  defaultPort: 3005,
  tools: [
    {
      name: 'servicenow_query_table',
      description: 'Query a ServiceNow table with optional filters.',
      inputSchema: {
        type: 'object',
        properties: {
          table: { type: 'string', description: 'e.g. incident, sys_user, cmdb_ci' },
          query: { type: 'string', description: 'Encoded query string' },
          fields: { type: 'array', items: { type: 'string' }, description: 'Fields to return' },
          limit: { type: 'number', default: 10 },
        },
        required: ['table'],
      },
    },
    {
      name: 'servicenow_get_record',
      description: 'Get a ServiceNow record by sys_id.',
      inputSchema: {
        type: 'object',
        properties: {
          table: { type: 'string' },
          sys_id: { type: 'string' },
        },
        required: ['table', 'sys_id'],
      },
    },
    {
      name: 'servicenow_list_tables',
      description: 'List common ServiceNow tables.',
      inputSchema: { type: 'object', properties: {} },
    },
  ],
  handler: async (name, args) => {
    switch (name) {
      case 'servicenow_query_table': return snow.queryTable(args.table, args.query, args.fields, args.limit);
      case 'servicenow_get_record': return snow.getRecord(args.table, args.sys_id);
      case 'servicenow_list_tables': return snow.listTables();
      default: throw new Error(`Unknown tool: ${name}`);
    }
  },
});
