// zod's own answers, from a bun probe of the original's schemas (the
// SDK's zod.gen.js and chord's STEER in src/acp/agent_app.ts) under zod
// 4.6.7: [method, params, format() tree when refused, parsed value when
// taken].
const zodAnswers = r'''
[
 [
  "initialize",
  {
   "protocolVersion": 1.5
  },
  {
   "_errors": [],
   "protocolVersion": {
    "_errors": [
     "Invalid input: expected int, received number"
    ]
   }
  },
  null
 ],
 [
  "initialize",
  {
   "protocolVersion": -1
  },
  {
   "_errors": [],
   "protocolVersion": {
    "_errors": [
     "Too small: expected number to be >=0"
    ]
   }
  },
  null
 ],
 [
  "initialize",
  {
   "protocolVersion": 70000
  },
  {
   "_errors": [],
   "protocolVersion": {
    "_errors": [
     "Too big: expected number to be <=65535"
    ]
   }
  },
  null
 ],
 [
  "initialize",
  {
   "protocolVersion": 1,
   "clientCapabilities": 3
  },
  null,
  {
   "protocolVersion": 1,
   "clientCapabilities": {
    "fs": {
     "readTextFile": false,
     "writeTextFile": false
    },
    "terminal": false,
    "auth": {
     "terminal": false
    }
   }
  }
 ],
 [
  "initialize",
  3,
  {
   "_errors": [
    "Invalid input: expected object, received number"
   ]
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "name": "a",
     "command": "x"
    }
   ]
  },
  {
   "_errors": [],
   "mcpServers": {
    "0": {
     "_errors": [],
     "url": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "headers": {
      "_errors": [
       "Invalid input: expected array, received undefined",
       "Invalid input: expected array, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"http\"",
       "Invalid input: expected \"sse\"",
       "Invalid input: expected \"acp\""
      ]
     },
     "serverId": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "args": {
      "_errors": [
       "Invalid input: expected array, received undefined"
      ]
     },
     "env": {
      "_errors": [
       "Invalid input: expected array, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "name": "a",
     "command": "x",
     "args": null,
     "env": [
      {
       "name": 1
      }
     ]
    }
   ]
  },
  {
   "_errors": [],
   "mcpServers": {
    "0": {
     "_errors": [],
     "url": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "headers": {
      "_errors": [
       "Invalid input: expected array, received undefined",
       "Invalid input: expected array, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"http\"",
       "Invalid input: expected \"sse\"",
       "Invalid input: expected \"acp\""
      ]
     },
     "serverId": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "env": {
      "0": {
       "_errors": [],
       "name": {
        "_errors": [
         "Invalid input: expected string, received number"
        ]
       },
       "value": {
        "_errors": [
         "Invalid input: expected string, received undefined"
        ]
       }
      },
      "_errors": []
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "type": "http",
     "name": "a",
     "url": "u"
    }
   ]
  },
  {
   "_errors": [],
   "mcpServers": {
    "0": {
     "_errors": [],
     "headers": {
      "_errors": [
       "Invalid input: expected array, received undefined",
       "Invalid input: expected array, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"sse\"",
       "Invalid input: expected \"acp\""
      ]
     },
     "serverId": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "command": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "args": {
      "_errors": [
       "Invalid input: expected array, received undefined"
      ]
     },
     "env": {
      "_errors": [
       "Invalid input: expected array, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "type": "http",
     "name": "a",
     "url": "u",
     "headers": []
    }
   ]
  },
  null,
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "name": "a",
     "url": "u",
     "headers": [],
     "type": "http"
    }
   ]
  }
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": 5
  },
  {
   "_errors": [],
   "mcpServers": {
    "_errors": [
     "Invalid input: expected array, received number"
    ]
   }
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [],
   "configOptions": [
    {
     "configId": "m"
    }
   ]
  },
  {
   "_errors": [],
   "configOptions": {
    "0": {
     "_errors": [],
     "type": {
      "_errors": [
       "Invalid input: expected \"boolean\""
      ]
     },
     "value": {
      "_errors": [
       "Invalid input: expected boolean, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [],
   "configOptions": [
    {
     "configId": "m",
     "value": "x"
    },
    {
     "type": "boolean",
     "configId": "b",
     "value": "no"
    }
   ]
  },
  null,
  {
   "cwd": "/w",
   "mcpServers": [],
   "configOptions": [
    {
     "value": "x",
     "configId": "m"
    },
    {
     "value": "no",
     "configId": "b"
    }
   ]
  }
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [],
   "configOptions": null,
   "additionalDirectories": [
    1
   ]
  },
  {
   "_errors": [],
   "additionalDirectories": {
    "0": {
     "_errors": [
      "Invalid input: expected string, received number"
     ]
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/list",
  {},
  null,
  {}
 ],
 [
  "session/list",
  {
   "cwd": null,
   "cursor": 2
  },
  {
   "_errors": [],
   "cursor": {
    "_errors": [
     "Invalid input: expected string, received number"
    ]
   }
  },
  null
 ],
 [
  "session/resume",
  {
   "sessionId": "s",
   "cwd": "/w",
   "mcpServers": null
  },
  null,
  {
   "sessionId": "s",
   "cwd": "/w",
   "mcpServers": []
  }
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "text",
     "text": "hi"
    },
    {
     "type": "image",
     "data": "d"
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "1": {
     "_errors": [],
     "text": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"text\"",
       "Invalid input: expected \"audio\"",
       "Invalid input: expected \"resource_link\"",
       "Invalid input: expected \"resource\""
      ]
     },
     "mimeType": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "name": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "uri": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "resource": {
      "_errors": [
       "Invalid input: expected object, received undefined",
       "Invalid input: expected object, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": "hi"
  },
  {
   "_errors": [],
   "prompt": {
    "_errors": [
     "Invalid input: expected array, received string"
    ]
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "resource",
     "resource": {
      "uri": "u",
      "text": "x"
     }
    },
    {
     "type": "resource_link",
     "uri": "u"
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "1": {
     "_errors": [],
     "text": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"text\"",
       "Invalid input: expected \"image\"",
       "Invalid input: expected \"audio\"",
       "Invalid input: expected \"resource\""
      ]
     },
     "data": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "mimeType": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "name": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "resource": {
      "_errors": [
       "Invalid input: expected object, received undefined",
       "Invalid input: expected object, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/set_config_option",
  {
   "sessionId": "s",
   "configId": "c",
   "value": "v"
  },
  null,
  {
   "value": "v",
   "sessionId": "s",
   "configId": "c"
  }
 ],
 [
  "session/set_config_option",
  {
   "sessionId": "s",
   "configId": "c",
   "type": "boolean",
   "value": "v"
  },
  null,
  {
   "value": "v",
   "sessionId": "s",
   "configId": "c"
  }
 ],
 [
  "session/set_config_option",
  7,
  {
   "_errors": [
    "Invalid input: expected object, received number",
    "Invalid input: expected object, received number",
    "Invalid input: expected object, received number"
   ]
  },
  null
 ],
 [
  "session/set_title",
  {
   "sessionId": 1,
   "title": null
  },
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received number"
    ]
   },
   "title": {
    "_errors": [
     "Invalid input: expected string, received null"
    ]
   }
  },
  null
 ],
 [
  "_chord/session/steer",
  {},
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   },
   "prompt": {
    "_errors": [
     "Invalid input: expected array, received undefined"
    ]
   }
  },
  null
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "resource",
     "resource": {
      "text": "x"
     }
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "type": {
      "_errors": [
       "Invalid input"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "audio"
    }
   ]
  },
  null,
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "audio"
    }
   ]
  }
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "text"
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "type": {
      "_errors": [
       "Invalid input"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": 3
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "type": {
      "_errors": [
       "Invalid input: expected \"text\"",
       "Invalid input: expected \"image\"",
       "Invalid input: expected \"resource\"",
       "Invalid input: expected \"resource_link\"",
       "Invalid input: expected string, received number"
      ]
     },
     "text": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "data": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "mimeType": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "resource": {
      "_errors": [
       "Invalid input: expected object, received undefined",
       "Invalid input: expected object, received undefined"
      ]
     },
     "uri": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "name": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    5
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number"
     ]
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "image",
     "data": "d",
     "mimeType": "m"
    },
    {
     "type": "resource_link",
     "uri": "u",
     "name": "n"
    }
   ]
  },
  null,
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "image",
     "data": "d",
     "mimeType": "m"
    },
    {
     "type": "resource_link",
     "uri": "u",
     "name": "n"
    }
   ]
  }
 ],
 [
  "initialize",
  {},
  {
   "_errors": [],
   "protocolVersion": {
    "_errors": [
     "Invalid input: expected number, received undefined"
    ]
   }
  },
  null
 ],
 [
  "initialize",
  {
   "protocolVersion": "x",
   "clientCapabilities": 3
  },
  {
   "_errors": [],
   "protocolVersion": {
    "_errors": [
     "Invalid input: expected number, received string"
    ]
   }
  },
  null
 ],
 [
  "session/new",
  {},
  {
   "_errors": [],
   "cwd": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   },
   "mcpServers": {
    "_errors": [
     "Invalid input: expected array, received undefined"
    ]
   }
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": 1,
   "mcpServers": [
    {
     "name": "a"
    }
   ]
  },
  {
   "_errors": [],
   "cwd": {
    "_errors": [
     "Invalid input: expected string, received number"
    ]
   },
   "mcpServers": {
    "0": {
     "_errors": [],
     "url": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "headers": {
      "_errors": [
       "Invalid input: expected array, received undefined",
       "Invalid input: expected array, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"http\"",
       "Invalid input: expected \"sse\"",
       "Invalid input: expected \"acp\""
      ]
     },
     "serverId": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "command": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "args": {
      "_errors": [
       "Invalid input: expected array, received undefined"
      ]
     },
     "env": {
      "_errors": [
       "Invalid input: expected array, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": null
  },
  null,
  {
   "cwd": "/w",
   "mcpServers": []
  }
 ],
 [
  "session/load",
  {},
  {
   "_errors": [],
   "mcpServers": {
    "_errors": [
     "Invalid input: expected array, received undefined"
    ]
   },
   "cwd": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   },
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   }
  },
  null
 ],
 [
  "session/resume",
  {},
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   },
   "cwd": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   }
  },
  null
 ],
 [
  "session/list",
  {
   "cwd": 3
  },
  {
   "_errors": [],
   "cwd": {
    "_errors": [
     "Invalid input: expected string, received number"
    ]
   }
  },
  null
 ],
 [
  "session/close",
  {},
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "text"
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "text": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "data": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "mimeType": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"image\"",
       "Invalid input: expected \"audio\"",
       "Invalid input: expected \"resource_link\"",
       "Invalid input: expected \"resource\""
      ]
     },
     "name": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "uri": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "resource": {
      "_errors": [
       "Invalid input: expected object, received undefined",
       "Invalid input: expected object, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "audio"
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "text": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"text\"",
       "Invalid input: expected \"image\"",
       "Invalid input: expected \"resource_link\"",
       "Invalid input: expected \"resource\""
      ]
     },
     "data": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "mimeType": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "name": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "uri": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "resource": {
      "_errors": [
       "Invalid input: expected object, received undefined",
       "Invalid input: expected object, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "weird"
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "text": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"text\"",
       "Invalid input: expected \"image\"",
       "Invalid input: expected \"audio\"",
       "Invalid input: expected \"resource_link\"",
       "Invalid input: expected \"resource\""
      ]
     },
     "data": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "mimeType": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "name": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "uri": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "resource": {
      "_errors": [
       "Invalid input: expected object, received undefined",
       "Invalid input: expected object, received undefined"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "resource",
     "resource": {
      "text": "x"
     }
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "text": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "type": {
      "_errors": [
       "Invalid input: expected \"text\"",
       "Invalid input: expected \"image\"",
       "Invalid input: expected \"audio\"",
       "Invalid input: expected \"resource_link\""
      ]
     },
     "data": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "mimeType": {
      "_errors": [
       "Invalid input: expected string, received undefined",
       "Invalid input: expected string, received undefined"
      ]
     },
     "name": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "uri": {
      "_errors": [
       "Invalid input: expected string, received undefined"
      ]
     },
     "resource": {
      "_errors": [],
      "uri": {
       "_errors": [
        "Invalid input: expected string, received undefined",
        "Invalid input: expected string, received undefined"
       ]
      },
      "blob": {
       "_errors": [
        "Invalid input: expected string, received undefined"
       ]
      }
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    3
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number",
      "Invalid input: expected object, received number"
     ]
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": 1,
   "prompt": [
    {
     "type": "text",
     "text": "a"
    },
    {
     "type": "image",
     "data": "d",
     "mimeType": "m"
    },
    {
     "type": "resource_link",
     "uri": "u",
     "name": "n"
    },
    {
     "type": "resource",
     "resource": {
      "uri": "u",
      "blob": "b"
     }
    }
   ]
  },
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received number"
    ]
   }
  },
  null
 ],
 [
  "session/cancel",
  {},
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   }
  },
  null
 ],
 [
  "session/set_config_option",
  {},
  {
   "_errors": [],
   "type": {
    "_errors": [
     "Invalid input: expected \"boolean\""
    ]
   },
   "value": {
    "_errors": [
     "Invalid input: expected boolean, received undefined",
     "Invalid input: expected string, received undefined"
    ]
   },
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   },
   "configId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   }
  },
  null
 ],
 [
  "session/set_config_option",
  {
   "sessionId": "s",
   "configId": "c",
   "value": true
  },
  {
   "_errors": [],
   "type": {
    "_errors": [
     "Invalid input: expected \"boolean\""
    ]
   },
   "value": {
    "_errors": [
     "Invalid input: expected string, received boolean"
    ]
   }
  },
  null
 ],
 [
  "session/set_config_option",
  {
   "sessionId": "s",
   "configId": "c",
   "value": 3
  },
  {
   "_errors": [],
   "type": {
    "_errors": [
     "Invalid input: expected \"boolean\""
    ]
   },
   "value": {
    "_errors": [
     "Invalid input: expected boolean, received number",
     "Invalid input: expected string, received number"
    ]
   }
  },
  null
 ],
 [
  "session/set_mode",
  {},
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   },
   "modeId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   }
  },
  null
 ],
 [
  "session/set_title",
  {},
  {
   "_errors": [],
   "sessionId": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   },
   "title": {
    "_errors": [
     "Invalid input: expected string, received undefined"
    ]
   }
  },
  null
 ],
 [
  "auth/status",
  {},
  null,
  {}
 ],
 [
  "auth/status",
  2,
  {
   "_errors": [
    "Invalid input: expected object, received number"
   ]
  },
  null
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "resource",
     "resource": {
      "uri": "u",
      "mimeType": 4,
      "text": "t"
     }
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "0": {
     "_errors": [],
     "type": {
      "_errors": [
       "Invalid input"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "text",
     "text": "a"
    },
    {
     "type": "resource_link",
     "uri": "u"
    }
   ]
  },
  {
   "_errors": [],
   "prompt": {
    "1": {
     "_errors": [],
     "type": {
      "_errors": [
       "Invalid input"
      ]
     }
    },
    "_errors": []
   }
  },
  null
 ],
 [
  "session/set_config_option",
  {
   "sessionId": "s",
   "configId": "mode",
   "type": "boolean",
   "value": "ask"
  },
  null,
  {
   "value": "ask",
   "sessionId": "s",
   "configId": "mode"
  }
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "type": "http",
     "name": "s",
     "command": "x",
     "args": [],
     "env": []
    }
   ]
  },
  null,
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "name": "s",
     "command": "x",
     "args": [],
     "env": []
    }
   ]
  }
 ],
 [
  "initialize",
  {
   "protocolVersion": 1,
   "clientCapabilities": {
    "subagents": 3
   }
  },
  null,
  {
   "protocolVersion": 1,
   "clientCapabilities": {
    "fs": {
     "readTextFile": false,
     "writeTextFile": false
    },
    "terminal": false,
    "auth": {
     "terminal": false
    }
   }
  }
 ],
 [
  "initialize",
  {
   "protocolVersion": 1
  },
  null,
  {
   "protocolVersion": 1,
   "clientCapabilities": {
    "fs": {
     "readTextFile": false,
     "writeTextFile": false
    },
    "terminal": false,
    "auth": {
     "terminal": false
    }
   }
  }
 ],
 [
  "initialize",
  {
   "protocolVersion": 1,
   "clientCapabilities": {
    "fs": {
     "readTextFile": true
    },
    "terminal": "yes",
    "plan": {},
    "session": {
     "notices": {},
     "compaction": 5,
     "configOptions": {
      "boolean": {}
     }
    },
    "elicitation": {
     "form": {},
     "url": 1
    },
    "extra": 1,
    "_meta": {
     "x": 1
    }
   },
   "clientInfo": {
    "name": "zed",
    "version": "1"
   },
   "_meta": null
  },
  null,
  {
   "protocolVersion": 1,
   "clientCapabilities": {
    "fs": {
     "readTextFile": true,
     "writeTextFile": false
    },
    "terminal": false,
    "session": {
     "configOptions": {
      "boolean": {}
     },
     "notices": {}
    },
    "plan": {},
    "auth": {
     "terminal": false
    },
    "elicitation": {
     "form": {}
    },
    "_meta": {
     "x": 1
    }
   },
   "clientInfo": {
    "name": "zed",
    "version": "1"
   },
   "_meta": null
  }
 ],
 [
  "initialize",
  {
   "protocolVersion": 1,
   "clientInfo": {
    "name": "zed"
   }
  },
  null,
  {
   "protocolVersion": 1,
   "clientCapabilities": {
    "fs": {
     "readTextFile": false,
     "writeTextFile": false
    },
    "terminal": false,
    "auth": {
     "terminal": false
    }
   }
  }
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "name": "a",
     "command": "x",
     "args": [
      "-y"
     ],
     "env": [
      {
       "name": "K",
       "value": "V",
       "extra": 1
      }
     ],
     "type": "stdio"
    },
    {
     "type": "sse",
     "name": "b",
     "url": "u",
     "headers": null,
     "_meta": 3
    }
   ],
   "configOptions": [
    {
     "configId": "m",
     "value": "x",
     "type": "select"
    }
   ],
   "extra": true,
   "_meta": {
    "a": 1
   }
  },
  null,
  {
   "cwd": "/w",
   "mcpServers": [
    {
     "name": "a",
     "command": "x",
     "args": [
      "-y"
     ],
     "env": [
      {
       "name": "K",
       "value": "V"
      }
     ]
    },
    {
     "name": "b",
     "url": "u",
     "headers": [],
     "type": "sse"
    }
   ],
   "configOptions": [
    {
     "value": "x",
     "configId": "m"
    }
   ],
   "_meta": {
    "a": 1
   }
  }
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [],
   "systemPrompt": {
    "mode": "append",
    "content": [
     {
      "type": "text",
      "text": "x"
     }
    ]
   }
  },
  null,
  {
   "cwd": "/w",
   "mcpServers": [],
   "systemPrompt": {
    "mode": "append",
    "content": [
     {
      "text": "x",
      "type": "text"
     }
    ]
   }
  }
 ],
 [
  "session/new",
  {
   "cwd": "/w",
   "mcpServers": [],
   "systemPrompt": {
    "mode": 1,
    "content": []
   }
  },
  {
   "_errors": [],
   "systemPrompt": {
    "_errors": [],
    "mode": {
     "_errors": [
      "Invalid input: expected \"append\"",
      "Invalid input: expected \"override\"",
      "Invalid input: expected string, received number"
     ]
    }
   }
  },
  null
 ],
 [
  "session/prompt",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "text",
     "text": "hi",
     "annotations": {
      "audience": [
       "user",
       "robot"
      ],
      "priority": "high"
     },
     "extra": 1
    },
    {
     "type": "image",
     "data": "d",
     "mimeType": "image/png",
     "uri": 5
    },
    {
     "type": "resource_link",
     "uri": "u",
     "name": "n",
     "size": 1.5,
     "title": "T"
    },
    {
     "type": "resource",
     "resource": {
      "uri": "u",
      "text": "x",
      "mimeType": null,
      "extra": 2
     },
     "_meta": {
      "m": 1
     }
    }
   ]
  },
  null,
  {
   "sessionId": "s",
   "prompt": [
    {
     "annotations": {
      "audience": [
       "user"
      ]
     },
     "text": "hi",
     "type": "text"
    },
    {
     "data": "d",
     "mimeType": "image/png",
     "type": "image"
    },
    {
     "name": "n",
     "title": "T",
     "uri": "u",
     "type": "resource_link"
    },
    {
     "resource": {
      "mimeType": null,
      "text": "x",
      "uri": "u"
     },
     "_meta": {
      "m": 1
     },
     "type": "resource"
    }
   ]
  }
 ],
 [
  "session/list",
  {
   "cwd": "/w",
   "archived": "only",
   "x": 1
  },
  null,
  {
   "cwd": "/w",
   "archived": "only"
  }
 ],
 [
  "session/resume",
  {
   "sessionId": "s",
   "cwd": "/w"
  },
  null,
  {
   "sessionId": "s",
   "cwd": "/w"
  }
 ],
 [
  "session/load",
  {
   "sessionId": "s",
   "cwd": "/w",
   "mcpServers": [],
   "additionalDirectories": null
  },
  null,
  {
   "mcpServers": [],
   "cwd": "/w",
   "additionalDirectories": [],
   "sessionId": "s"
  }
 ],
 [
  "session/cancel",
  {
   "sessionId": "s",
   "x": 1
  },
  null,
  {
   "sessionId": "s"
  }
 ],
 [
  "session/set_config_option",
  {
   "sessionId": "s",
   "configId": "fast",
   "type": "boolean",
   "value": true,
   "x": 1
  },
  null,
  {
   "type": "boolean",
   "value": true,
   "sessionId": "s",
   "configId": "fast"
  }
 ],
 [
  "session/set_mode",
  {
   "sessionId": "s",
   "modeId": "ask",
   "_meta": "bad"
  },
  null,
  {
   "sessionId": "s",
   "modeId": "ask"
  }
 ],
 [
  "session/set_title",
  {
   "sessionId": "s",
   "title": "T"
  },
  null,
  {
   "sessionId": "s",
   "title": "T"
  }
 ],
 [
  "session/close",
  {
   "sessionId": "s"
  },
  null,
  {
   "sessionId": "s"
  }
 ],
 [
  "auth/status",
  {
   "x": 1,
   "_meta": {
    "y": 2
   }
  },
  null,
  {
   "_meta": {
    "y": 2
   }
  }
 ],
 [
  "_chord/session/steer",
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "text",
     "text": "a",
     "extra": 1
    },
    {
     "type": "audio",
     "data": "d"
    },
    {
     "extra": 0,
     "type": "resource",
     "resource": {
      "blob": "b",
      "uri": "u",
      "k": 1
     }
    }
   ],
   "x": 1
  },
  null,
  {
   "sessionId": "s",
   "prompt": [
    {
     "type": "text",
     "text": "a",
     "extra": 1
    },
    {
     "type": "audio",
     "data": "d"
    },
    {
     "type": "resource",
     "resource": {
      "uri": "u",
      "blob": "b",
      "k": 1
     },
     "extra": 0
    }
   ]
  }
 ]
]
''';
