#!/usr/bin/env node

import { createMCPServer } from './shared.js';
import { SalesforceConnector } from '../connectors/salesforce.js';

const sf = new SalesforceConnector(
  process.env.SALESFORCE_INSTANCE_URL,
  process.env.SALESFORCE_ACCESS_TOKEN
);

await createMCPServer({
  name: 'ibex-salesforce',
  defaultPort: 3006,
  tools: [
    {
      name: 'salesforce_soql_query',
      description: 'Run a SOQL query against Salesforce.',
      inputSchema: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'SOQL query string' },
          limit: { type: 'number', default: 50 },
        },
        required: ['query'],
      },
    },
    {
      name: 'salesforce_get_record',
      description: 'Get a Salesforce record by object type and ID.',
      inputSchema: {
        type: 'object',
        properties: {
          object_type: { type: 'string', description: 'e.g. Account, Contact, Opportunity' },
          record_id: { type: 'string', description: 'Salesforce record ID' },
          fields: { type: 'array', items: { type: 'string' }, description: 'Specific fields to return' },
        },
        required: ['object_type', 'record_id'],
      },
    },
    {
      name: 'salesforce_search',
      description: 'Global search across Salesforce objects (Accounts, Contacts, Opportunities, Cases, Leads).',
      inputSchema: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Search term' },
          limit: { type: 'number', default: 20 },
        },
        required: ['query'],
      },
    },
    {
      name: 'salesforce_describe_object',
      description: 'Get the schema/fields of a Salesforce object.',
      inputSchema: {
        type: 'object',
        properties: {
          object_type: { type: 'string', description: 'e.g. Account, Contact, Opportunity' },
        },
        required: ['object_type'],
      },
    },
    {
      name: 'salesforce_list_objects',
      description: 'List available Salesforce objects.',
      inputSchema: { type: 'object', properties: {} },
    },
  ],
  handler: async (name, args) => {
    switch (name) {
      case 'salesforce_soql_query': return sf.soqlQuery(args.query, args.limit);
      case 'salesforce_get_record': return sf.getRecord(args.object_type, args.record_id, args.fields);
      case 'salesforce_search': return sf.globalSearch(args.query, args.limit);
      case 'salesforce_describe_object': return sf.describeObject(args.object_type);
      case 'salesforce_list_objects': return sf.listObjects();
      default: throw new Error(`Unknown tool: ${name}`);
    }
  },
});
