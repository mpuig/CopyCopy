import Foundation

enum BuiltInSkills {
    static let all: [(id: String, content: String)] = [
        ("urls", urls),
        ("files", files),
        ("images", images),
        ("text", text),
        ("places", places),
        ("code", code),
        ("transform", transform),
        ("filesystem", filesystem),
    ]

    static let urls = """
---
name: urls
description: Open, search, and act on copied URLs, links, and web addresses
compatibility: macOS 14+
metadata:
  copycopy-content-types: "url"
---

# URLs

Activates when a URL or web link is on the clipboard.

## Tools

```json
[
  {
    "id": "open-url",
    "name": "Open URL",
    "description": "Open URL in default browser",
    "icon": "link",
    "execute": "openURL",
    "parameters": {
      "type": "object",
      "properties": {
        "url": {"type": "string", "description": "Clipboard URL", "source": "clipboardURL"}
      },
      "required": ["url"]
    }
  }
]
```
"""

    static let files = """
---
name: files
description: Open or reveal copied files and directories
compatibility: macOS 14+
metadata:
  copycopy-content-types: "files"
---

# Files

Activates when one or more file paths are on the clipboard.

## Tools

```json
[
  {
    "id": "open-file",
    "name": "Open File",
    "description": "Open File",
    "icon": "doc",
    "execute": "openFile",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  },
  {
    "id": "reveal-in-finder",
    "name": "Reveal in Finder",
    "description": "Reveal in Finder",
    "icon": "folder",
    "execute": "revealInFinder",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  }
]
```
"""

    static let images = """
---
name: images
description: Save and export copied images from the clipboard
compatibility: macOS 14+
metadata:
  copycopy-content-types: "image"
---

# Images

Activates when an image is on the clipboard.

## Tools

```json
[
  {
    "id": "save-image",
    "name": "Save Image",
    "description": "Save Image…",
    "icon": "square.and.arrow.down",
    "execute": "saveImage",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  }
]
```
"""

    static let text = """
---
name: text
description: Search or look up general copied text
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
---

# Text

Activates for any plain or rich text on the clipboard. These are the default general-purpose text actions.

## Tools

```json
[
  {
    "id": "search-web",
    "name": "Search the Web",
    "description": "Search the Web",
    "icon": "magnifyingglass",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Search endpoint", "source": "literal", "value": "https://duckduckgo.com/"},
        "q": {"type": "string", "description": "Search query", "source": "clipboard"}
      },
      "required": ["baseURL", "q"]
    }
  },
  {
    "id": "dictionary",
    "name": "Look up in Dictionary",
    "description": "Look up in Dictionary",
    "icon": "book",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Dictionary scheme", "source": "literal", "value": "dict://"},
        "path": {"type": "string", "description": "Dictionary lookup text", "source": "clipboard"}
      },
      "required": ["baseURL", "path"]
    }
  },
  {
    "id": "html-to-markdown",
    "name": "Convert HTML to Markdown",
    "description": "Convert HTML to Markdown",
    "icon": "arrow.down.doc.text",
    "execute": "htmlToMarkdown",
    "parameters": {
      "type": "object",
      "properties": {
        "html": {"type": "string", "description": "Clipboard HTML", "source": "clipboard"}
      },
      "required": ["html"]
    },
    "entityTypes": ["html"]
  }
]
```
"""

    static let contacts = """
---
name: contacts
description: Call, email, message, or look up people by name, email address, or phone number
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "personalName,email,phoneNumber"
---

# Contacts

Activates when the clipboard contains a person's name, email address, or phone number. Actions are filtered to the specific entity detected.

## Tools

```json
[
  {
    "id": "search-linkedin",
    "name": "Search LinkedIn",
    "description": "Search LinkedIn",
    "icon": "person.crop.circle",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "LinkedIn search", "source": "literal", "value": "https://www.linkedin.com/search/results/all/"},
        "keywords": {"type": "string", "description": "Search keywords", "source": "clipboard"}
      },
      "required": ["baseURL", "keywords"]
    },
    "entityTypes": ["personalName"]
  },
  {
    "id": "add-to-contacts",
    "name": "Add to Contacts",
    "description": "Add to Contacts",
    "icon": "person.badge.plus",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Contacts endpoint", "source": "literal", "value": "addressbook://contact"},
        "name": {"type": "string", "description": "Contact name", "source": "clipboard"}
      },
      "required": ["baseURL", "name"]
    },
    "entityTypes": ["personalName"]
  },
  {
    "id": "compose-email",
    "name": "Compose Email",
    "description": "Compose Email",
    "icon": "envelope",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Mail scheme", "source": "literal", "value": "mailto:"},
        "path": {"type": "string", "description": "Email address", "source": "clipboard"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["email"]
  },
  {
    "id": "add-contact-email",
    "name": "Add to Contacts",
    "description": "Add to Contacts",
    "icon": "person.badge.plus",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Contacts endpoint", "source": "literal", "value": "addressbook://contact"},
        "email": {"type": "string", "description": "Email address", "source": "clipboard"}
      },
      "required": ["baseURL", "email"]
    },
    "entityTypes": ["email"]
  },
  {
    "id": "call",
    "name": "Call",
    "description": "Call",
    "icon": "phone",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Telephone scheme", "source": "literal", "value": "tel:"},
        "path": {"type": "string", "description": "Phone number", "source": "clipboard"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["phoneNumber"]
  },
  {
    "id": "send-message",
    "name": "Send Message",
    "description": "Send Message",
    "icon": "message",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "SMS scheme", "source": "literal", "value": "sms:"},
        "path": {"type": "string", "description": "Phone number", "source": "clipboard"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["phoneNumber"]
  }
]
```
"""

    static let places = """
---
name: places
description: Open places, addresses, and GPS coordinates in Apple Maps or Google Maps
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "placeName,address,coordinates"
---

# Places

Activates when the clipboard contains a place name, street address, or GPS coordinates.

## Tools

```json
[
  {
    "id": "open-maps",
    "name": "Open in Maps",
    "description": "Open in Maps",
    "icon": "map",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Apple Maps URL", "source": "literal", "value": "maps://"},
        "q": {"type": "string", "description": "Place name", "source": "clipboard"}
      },
      "required": ["baseURL", "q"]
    },
    "entityTypes": ["placeName"]
  },
  {
    "id": "open-maps-address",
    "name": "Open in Maps",
    "description": "Open in Maps",
    "icon": "map",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Apple Maps URL", "source": "literal", "value": "maps://"},
        "address": {"type": "string", "description": "Street address", "source": "clipboard"}
      },
      "required": ["baseURL", "address"]
    },
    "entityTypes": ["address"]
  },
  {
    "id": "open-maps-coords",
    "name": "Open in Maps",
    "description": "Open in Maps",
    "icon": "mappin.and.ellipse",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Apple Maps URL", "source": "literal", "value": "maps://"},
        "ll": {"type": "string", "description": "Coordinates", "source": "clipboardTrimmed"}
      },
      "required": ["baseURL", "ll"]
    },
    "entityTypes": ["coordinates"]
  },
  {
    "id": "google-maps",
    "name": "Open in Google Maps",
    "description": "Open in Google Maps",
    "icon": "map",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Google Maps URL", "source": "literal", "value": "https://www.google.com/maps"},
        "q": {"type": "string", "description": "Coordinates", "source": "clipboardTrimmed"}
      },
      "required": ["baseURL", "q"]
    },
    "entityTypes": ["coordinates"]
  }
]
```
"""

    static let code = """
---
name: code
description: Format JSON, decode encoded text, and open code-like content as a temp file
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "json,base64,urlEncoded,markdown,codeSnippet,shellCommand,logOutput,sql"
---

# Code

Activates when the clipboard contains JSON, Base64, URL-encoded text, or code-like content.

## Tools

```json
[
  {
    "id": "pretty-json",
    "name": "Pretty Print JSON",
    "description": "Pretty Print JSON",
    "icon": "curlybraces",
    "execute": "formatJSON",
    "parameters": {
      "type": "object",
      "properties": {
        "json": {"type": "string", "description": "Clipboard JSON", "source": "clipboard"}
      },
      "required": ["json"]
    },
    "entityTypes": ["json"]
  },
  {
    "id": "decode-base64",
    "name": "Decode Base64",
    "description": "Decode Base64",
    "icon": "arrow.down.doc",
    "execute": "decodeBase64",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {"type": "string", "description": "Clipboard Base64", "source": "clipboard"}
      },
      "required": ["text"]
    },
    "entityTypes": ["base64"]
  },
  {
    "id": "decode-url",
    "name": "Decode URL Encoding",
    "description": "Decode URL Encoding",
    "icon": "arrow.down.doc",
    "execute": "decodeURL",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {"type": "string", "description": "Clipboard URL-encoded text", "source": "clipboard"}
      },
      "required": ["text"]
    },
    "entityTypes": ["urlEncoded"]
  },
  {
    "id": "open-temp-code",
    "name": "Open as Temp File",
    "description": "Open as Temp File",
    "icon": "doc.badge.plus",
    "execute": "saveTempFile",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {"type": "string", "description": "Clipboard text", "source": "clipboard"}
      },
      "required": ["text"]
    },
    "entityTypes": ["markdown", "codeSnippet", "shellCommand", "logOutput", "sql"]
  }
]
```
"""

    static let social = """
---
name: social
description: Search hashtags on Twitter/X, open user profiles on Twitter or GitHub, and preview hex colors
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "hashtag,mention,hexColor"
---

# Social

Activates when the clipboard contains a hashtag (#topic), mention (@user), or hex color (#ff0000).

## Tools

```json
[
  {
    "id": "search-twitter",
    "name": "Search Twitter/X",
    "description": "Search Twitter/X",
    "icon": "number",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Twitter search", "source": "literal", "value": "https://twitter.com/search"},
        "q": {"type": "string", "description": "Hashtag query", "source": "clipboard"}
      },
      "required": ["baseURL", "q"]
    },
    "entityTypes": ["hashtag"]
  },
  {
    "id": "twitter-profile",
    "name": "Open Twitter/X Profile",
    "description": "Open Twitter/X Profile",
    "icon": "at",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Twitter profile URL", "source": "literal", "value": "https://twitter.com/"},
        "path": {"type": "string", "description": "Profile handle", "source": "clipboard"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["mention"]
  },
  {
    "id": "github-profile",
    "name": "Open GitHub Profile",
    "description": "Open GitHub Profile",
    "icon": "person.circle",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "GitHub profile URL", "source": "literal", "value": "https://github.com/"},
        "path": {"type": "string", "description": "Profile handle", "source": "clipboard"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["mention"]
  },
  {
    "id": "preview-color",
    "name": "Preview Color",
    "description": "Preview Color",
    "icon": "paintpalette",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Color preview URL", "source": "literal", "value": "https://www.color-hex.com/color/"},
        "path": {"type": "string", "description": "Hex color", "source": "clipboardTrimmed"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["hexColor"]
  }
]
```
"""

    static let tracking = """
---
name: tracking
description: Track flights, packages, and look up or ping IP addresses
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "transitInfo,trackingNumber,ipAddress"
---

# Tracking

Activates when the clipboard contains a flight number, package tracking number, or IP address.

## Tools

```json
[
  {
    "id": "track-flight",
    "name": "Track Flight",
    "description": "Track Flight",
    "icon": "airplane",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "FlightAware URL", "source": "literal", "value": "https://www.flightaware.com/live/flight/"},
        "path": {"type": "string", "description": "Flight number", "source": "clipboard"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["transitInfo"]
  },
  {
    "id": "track-package",
    "name": "Track Package",
    "description": "Track Package",
    "icon": "shippingbox",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Search URL", "source": "literal", "value": "https://www.google.com/search"},
        "q": {"type": "string", "description": "Tracking query", "source": "clipboard", "prefix": "track "}
      },
      "required": ["baseURL", "q"]
    },
    "entityTypes": ["trackingNumber"]
  },
  {
    "id": "lookup-ip",
    "name": "Lookup IP",
    "description": "Lookup IP",
    "icon": "network",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "IP info URL", "source": "literal", "value": "https://ipinfo.io/"},
        "path": {"type": "string", "description": "IP address", "source": "clipboardTrimmed"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["ipAddress"]
  },
  {
    "id": "ping",
    "name": "Ping",
    "description": "Ping",
    "icon": "antenna.radiowaves.left.and.right",
    "execute": "ping",
    "parameters": {
      "type": "object",
      "properties": {
        "host": {"type": "string", "description": "Hostname or IP", "source": "clipboardTrimmed"}
      },
      "required": ["host"]
    },
    "entityTypes": ["ipAddress"]
  }
]
```
"""

static let transform = """
---
name: transform
description: Summarize, rewrite, and translate text using on-device AI (LFM 2.5). No data leaves your Mac.
compatibility: macOS 14+, requires LFM 2.5 model download
metadata:
  copycopy-content-types: "text"
---

# Transform

AI-powered text transformations using the on-device LFM 2.5 model. Results are copied to the clipboard.

## Tools

```json
[
  {
    "id": "summarize",
    "name": "Summarize Content",
    "description": "Summarize Content",
    "icon": "text.redaction",
    "execute": "llmPrompt",
    "parameters": {
      "type": "object",
      "properties": {
        "systemPrompt": {
          "type": "string",
          "description": "Structured summarization instruction",
          "source": "literal",
          "value": "Summarize the clipboard text into a short, clear summary. Preserve the main point and the most important supporting details. Omit repetition, filler, and minor examples. Use a neutral professional tone. Default to 3-5 bullet points. If the source is very short, return a single sentence. Do not add headings, commentary, or information not present in the source."
        },
        "prompt": {"type": "string", "description": "Clipboard text", "source": "clipboard"}
      },
      "required": ["systemPrompt", "prompt"]
    }
  },
  {
    "id": "translate",
    "name": "Translate",
    "description": "Translate",
    "icon": "globe",
    "execute": "llmPrompt",
    "parameters": {
      "type": "object",
      "properties": {
        "systemPrompt": {
          "type": "string",
          "description": "Translation instruction",
          "source": "literal",
          "value": "Translate the clipboard text to English. Return only the translation with no explanation."
        },
        "prompt": {"type": "string", "description": "Clipboard text", "source": "clipboard"}
      },
      "required": ["systemPrompt", "prompt"]
    },
    "entityTypes": ["foreignLanguage"]
  },
  {
    "id": "rewrite-email-draft",
    "name": "Rewrite Email Draft",
    "description": "Rewrite Email Draft",
    "icon": "envelope.badge",
    "execute": "llmPrompt",
    "parameters": {
      "type": "object",
      "properties": {
        "systemPrompt": {
          "type": "string",
          "description": "Email rewrite instruction",
          "source": "literal",
          "value": "Rewrite the clipboard text as a polished email reply draft. Preserve the original intent, key facts, commitments, and requested actions. Improve clarity, grammar, tone, and structure. Keep it concise and natural. Return only the rewritten email body with no commentary, subject line, or markdown."
        },
        "prompt": {"type": "string", "description": "Clipboard text", "source": "clipboard"}
      },
      "required": ["systemPrompt", "prompt"]
    },
    "entityTypes": ["emailDraft"]
  },
  {
    "id": "rewrite-slack-message",
    "name": "Rewrite Slack Message",
    "description": "Rewrite Slack Message",
    "icon": "message.badge",
    "execute": "llmPrompt",
    "parameters": {
      "type": "object",
      "properties": {
        "systemPrompt": {
          "type": "string",
          "description": "Slack rewrite instruction",
          "source": "literal",
          "value": "Rewrite the clipboard text as a polished Slack message. Preserve the original intent, key facts, commitments, and requested actions. Improve clarity, tone, and structure while keeping it concise, natural, and conversational. Return only the rewritten message with no commentary or markdown."
        },
        "prompt": {"type": "string", "description": "Clipboard text", "source": "clipboard"}
      },
      "required": ["systemPrompt", "prompt"]
    },
    "entityTypes": ["slackDraft"]
  }
]
```
"""

    static let finance = """
---
name: finance
description: Convert currencies using Google search
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "currency"
---

# Finance

Activates when the clipboard contains a currency amount (e.g. "$100", "50 EUR").

## Tools

```json
[
  {
    "id": "convert-currency",
    "name": "Convert Currency",
    "description": "Convert Currency",
    "icon": "dollarsign.circle",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Search URL", "source": "literal", "value": "https://www.google.com/search"},
        "q": {"type": "string", "description": "Currency query", "source": "clipboard", "suffix": " to EUR"}
      },
      "required": ["baseURL", "q"]
    },
    "entityTypes": ["currency"]
  }
]
```
"""

    static let datetime = """
---
name: datetime
description: Create calendar events from copied dates and times
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "date"
---

# Date & Time

Activates when the clipboard contains a date or time reference.

## Tools

```json
[
  {
    "id": "create-event",
    "name": "Create Calendar Event",
    "description": "Create Calendar Event",
    "icon": "calendar.badge.plus",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Calendar scheme", "source": "literal", "value": "calshow:"},
        "path": {"type": "string", "description": "Calendar payload", "source": "clipboardTrimmed"}
      },
      "required": ["baseURL", "path"]
    },
    "entityTypes": ["date"]
  }
]
```
"""

    static let filesystem = """
---
name: filesystem
description: Reveal file paths in Finder or open them in Terminal
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "filePath"
---

# Filesystem

Activates when the clipboard contains a file or directory path (e.g. /Users/me/Documents).

## Tools

```json
[
  {
    "id": "reveal-path",
    "name": "Reveal in Finder",
    "description": "Reveal in Finder",
    "icon": "folder",
    "execute": "revealPath",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {"type": "string", "description": "Clipboard path", "source": "clipboardTrimmed"}
      },
      "required": ["path"]
    },
    "entityTypes": ["filePath"]
  },
  {
    "id": "open-terminal",
    "name": "Open in Terminal",
    "description": "Open in Terminal",
    "icon": "terminal",
    "execute": "openInTerminal",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {"type": "string", "description": "Clipboard path", "source": "clipboardTrimmed"}
      },
      "required": ["path"]
    },
    "entityTypes": ["filePath"]
  }
]
```
"""

    static let identity = """
---
name: identity
description: Actions for UUIDs, organization names, and unique identifiers
compatibility: macOS 14+
metadata:
  copycopy-content-types: "text"
  copycopy-entity-types: "uuid,organizationName"
---

# Identity

Activates when the clipboard contains a UUID or organization name.

## Tools

```json
[
  {
    "id": "copy-lowercase",
    "name": "Copy Lowercase UUID",
    "description": "Copy Lowercase UUID",
    "icon": "textformat.abc",
    "execute": "copyToClipboard",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {"type": "string", "description": "Clipboard UUID", "source": "clipboardTrimmed"}
      },
      "required": ["text"]
    },
    "entityTypes": ["uuid"]
  },
  {
    "id": "search-company",
    "name": "Search Company",
    "description": "Search Company",
    "icon": "building.2",
    "execute": "openURLTemplate",
    "parameters": {
      "type": "object",
      "properties": {
        "baseURL": {"type": "string", "description": "Search URL", "source": "literal", "value": "https://www.google.com/search"},
        "q": {"type": "string", "description": "Company search query", "source": "clipboard", "suffix": " company"}
      },
      "required": ["baseURL", "q"]
    },
    "entityTypes": ["organizationName"]
  }
]
```
"""
}
