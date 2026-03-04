import fetch from 'node-fetch';

export class SalesforceConnector {
  constructor(instanceUrl, accessToken) {
    this.instanceUrl = instanceUrl.replace(/\/$/, '');
    this.accessToken = accessToken;
    this.apiVersion = 'v62.0';
    this.baseUrl = `${this.instanceUrl}/services/data/${this.apiVersion}`;
  }

  async apiCall(endpoint, method = 'GET', body = null) {
    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: body ? JSON.stringify(body) : null,
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Salesforce API error: ${response.status} - ${error}`);
    }

    return response.json();
  }

  async soqlQuery(query, limit = 50) {
    const limitedQuery = query.includes('LIMIT')
      ? query
      : `${query} LIMIT ${Math.min(limit, 200)}`;

    const data = await this.apiCall(`/query?q=${encodeURIComponent(limitedQuery)}`);

    return {
      total_size: data.totalSize,
      done: data.done,
      records: (data.records || []).map(r => {
        const { attributes, ...fields } = r;
        return {
          type: attributes?.type,
          url: attributes?.url,
          ...fields,
        };
      }),
    };
  }

  async getRecord(objectType, recordId, fields = null) {
    let endpoint = `/sobjects/${objectType}/${recordId}`;
    if (fields?.length) {
      endpoint += `?fields=${fields.join(',')}`;
    }

    const data = await this.apiCall(endpoint);
    const { attributes, ...fields_ } = data;

    return {
      type: attributes?.type,
      url: attributes?.url,
      ...fields_,
    };
  }

  async describeObject(objectType) {
    const data = await this.apiCall(`/sobjects/${objectType}/describe`);

    return {
      name: data.name,
      label: data.label,
      label_plural: data.labelPlural,
      key_prefix: data.keyPrefix,
      queryable: data.queryable,
      searchable: data.searchable,
      fields: data.fields?.map(f => ({
        name: f.name,
        label: f.label,
        type: f.type,
        length: f.length,
        required: !f.nillable && !f.defaultedOnCreate,
        updateable: f.updateable,
        reference_to: f.referenceTo?.length ? f.referenceTo : undefined,
      })) || [],
    };
  }

  async globalSearch(query, limit = 20) {
    const sosl = `FIND {${query}} IN ALL FIELDS RETURNING Account(Id,Name,Type,Industry LIMIT ${limit}), Contact(Id,Name,Email,Account.Name LIMIT ${limit}), Opportunity(Id,Name,StageName,Amount,CloseDate LIMIT ${limit}), Case(Id,CaseNumber,Subject,Status,Priority LIMIT ${limit}), Lead(Id,Name,Email,Company,Status LIMIT ${limit})`;

    const data = await this.apiCall(`/search?q=${encodeURIComponent(sosl)}`);

    const results = {};
    for (const group of data.searchRecords || []) {
      const type = group.attributes?.type;
      if (!results[type]) results[type] = [];
      const { attributes, ...fields } = group;
      results[type].push(fields);
    }

    return {
      query,
      results,
    };
  }

  async listObjects() {
    const data = await this.apiCall('/sobjects');

    return {
      objects: (data.sobjects || [])
        .filter(o => o.queryable && !o.deprecatedAndHidden)
        .map(o => ({
          name: o.name,
          label: o.label,
          key_prefix: o.keyPrefix,
          queryable: o.queryable,
          searchable: o.searchable,
          custom: o.custom,
        })),
    };
  }
}
