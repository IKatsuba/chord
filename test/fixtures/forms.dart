// What the fake agent's `form` and `link` scenarios ask for, as the
// original's tests/fixtures/forms.ts has it.

/// The `form` scenario's fields: one of each kind a form can ask for.
const formSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'name': {
      'type': 'string',
      'title': 'Project name',
      'description': 'Lowercase, dashes allowed',
      'minLength': 3,
      'maxLength': 20,
    },
    'email': {'type': 'string', 'title': 'Contact email', 'format': 'email'},
    'replicas': {
      'type': 'integer',
      'title': 'Replicas',
      'minimum': 1,
      'maximum': 9,
      'default': 2,
    },
    'ratio': {
      'type': 'number',
      'title': 'Traffic share',
      'description': 'Share of traffic sent here, from 0 to 1',
      'minimum': 0,
      'maximum': 1,
    },
    'public': {'type': 'boolean', 'title': 'Public', 'default': false},
    'region': {
      'type': 'string',
      'title': 'Region',
      'oneOf': [
        {'const': 'eu', 'title': 'Europe'},
        {'const': 'us', 'title': 'United States'},
        {'const': 'ap', 'title': 'Asia Pacific'},
      ],
    },
    'tags': {
      'type': 'array',
      'title': 'Tags',
      'items': {
        'type': 'string',
        'enum': ['web', 'api', 'worker'],
      },
    },
  },
  'required': ['name', 'replicas', 'region'],
};

/// The `link` scenario's link.
const linkUrl = 'https://example.com/oauth/authorize?client=abc&state=9f2c';
