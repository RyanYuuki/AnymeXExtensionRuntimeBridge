import 'package:flutter_qjs/flutter_qjs.dart';

class JsLibs {
  late JavascriptRuntime runtime;
  JsLibs(this.runtime);

  void init() {
    runtime.onMessage('log', (dynamic args) {
      return null;
    });
    runtime.onMessage('urlencode', (dynamic args) {
      return Uri.encodeComponent(args[0]);
    });
    runtime.onMessage('urldecode', (dynamic args) {
      return Uri.decodeComponent(args[0]);
    });

    runtime.evaluate('''
console.log = function (message) {
    if (typeof message === "object") {
         message = JSON.stringify(message);
      }
    sendMessage("log", JSON.stringify([message ? message.toString() : ""]));
};
console.warn = function (message) {
    if (typeof message === "object") {
         message = JSON.stringify(message);
      }
    sendMessage("log", JSON.stringify([message ? message.toString() : ""]));
};
console.error = function (message) {
    if (typeof message === "object") {
         message = JSON.stringify(message);
      }
    sendMessage("log", JSON.stringify([message ? message.toString() : ""]));
};
String.prototype.substringAfter = function(pattern) {
    const startIndex = this.indexOf(pattern);
    if (startIndex === -1) return this.substring(0);

    const start = startIndex + pattern.length;
    return this.substring(start);
};

String.prototype.substringAfterLast = function(pattern) {
    return this.split(pattern).pop();
};

String.prototype.substringBefore = function(pattern) {
    const endIndex = this.indexOf(pattern);
    if (endIndex === -1) return this.substring(0);

    return this.substring(0, endIndex);
};

String.prototype.substringBeforeLast = function(pattern) {
    const endIndex = this.lastIndexOf(pattern);
    if (endIndex === -1) return this.substring(0);
    return this.substring(0, endIndex);
};

String.prototype.substringBetween = function(left, right) {
    let startIndex = 0;
    let index = this.indexOf(left, startIndex);
    if (index === -1) return "";
    let leftIndex = index + left.length;
    let rightIndex = this.indexOf(right, leftIndex);
    if (rightIndex === -1) return "";
    startIndex = rightIndex + right.length;
    return this.substring(leftIndex, rightIndex);
};

async function jsonStringify(fn) {
    return JSON.stringify(await fn());
}

const isUrlAbsolute = url => {
  if (url) {
    if (url.indexOf("//") === 0) {
      return true;
    }
    if (url.indexOf("://") === -1) {
      return false;
    }
    if (url.indexOf(".") === -1) {
      return false;
    }
    if (url.indexOf("/") === -1) {
      return false;
    }
    if (url.indexOf(":") > url.indexOf("/")) {
      return false;
    }
    if (url.indexOf("://") < url.indexOf(".")) {
      return true;
    }
  }
  return false;
};

const NovelStatus = {
  "Unknown": "Unknown",
  "Ongoing": "Ongoing",
  "Completed": "Completed",
  "Licensed": "Licensed",
  "PublishingFinished": "Publishing Finished",
  "Cancelled": "Cancelled",
  "OnHiatus": "On Hiatus"
};

const FilterTypes = {
  "TextInput": "Text",
  "Picker": "Picker",
  "CheckboxGroup": "Checkbox",
  "Switch": "Switch",
  "ExcludableCheckboxGroup": "XCheckbox"
};

const isPickerValue = q => {
  return q && q.type === FilterTypes.Picker && typeof q.value === "string";
};

const isCheckboxValue = q => {
  return q && q.type === FilterTypes.CheckboxGroup && Array.isArray(q.value);
};

const isSwitchValue = q => {
  return q && q.type === FilterTypes.Switch && typeof q.value === "boolean";
};

const isTextValue = q => {
  return q && q.type === FilterTypes.TextInput && typeof q.value === "string";
};

const isXCheckboxValue = q => {
  return (
    q &&
    q.type === FilterTypes.ExcludableCheckboxGroup &&
    typeof q.value === "object" &&
    !Array.isArray(q.value)
  );
};

function urlencode(input) {
    return sendMessage(
        "urlencode",
        JSON.stringify([input])
    );
}
function urldecode(input) {
    return sendMessage(
        "urldecode",
        JSON.stringify([input])
    );
}

async function fetchText(url, init, encoding) {
  try {
    const res = await fetchApi(url, init);
    if (!res.ok) {
      return "";
    }
    return await res.text();
  } catch (e) {
    return "";
  }
}

async function fetchProto(protoInit, url, init) {
  return fetchApi(url, init);
}

async function fetchViaWebview(url, options) {
  const res = await fetchApi(url, options);
  const text = await res.text();
  return {
    ok: res.ok,
    url: res.url || url,
    html: text,
    title: ""
  };
}

const PluginError = {
  Captcha: "Captcha error, please open in webview",
  Cloudflare: "Cloudflare is blocking requests. Try again later.",
  RateLimited: "Too many requests (429). Please try again later.",
  NotFound: "Content not found (404), it may have been removed from this source.",
  NovelNotFound: "Novel not found (404), it may have been removed from this source.",
  ChapterNotFound: "Chapter not found (404), it may have been removed from this source.",
  AuthRequired: "Authentication required. Please log in via WebView.",
  EmptyContent: "No readable content was found.",
  InvalidResponse: "Invalid response from source.",
  NetworkError: "Could not reach site, please try to open in webview."
};

function createPluginError(code, options) {
  var message = (options && options.message) || code;
  var error = new Error(message);
  error.name = "PluginError";
  error.code = code;
  if (options && options.status !== undefined) {
    error.status = options.status;
  }
  if (options && options.url) {
    error.url = options.url;
  }
  return error;
}

function httpError(status, message, url) {
  var code = status === 401 ? PluginError.AuthRequired
    : status === 403 ? PluginError.Cloudflare
    : status === 404 ? PluginError.NotFound
    : status === 429 ? PluginError.RateLimited
    : status === 503 ? PluginError.Cloudflare
    : PluginError.NetworkError;
  var fallbackMessage = code === PluginError.NetworkError && status
    ? "Could not reach site (" + status + "), please try to open in webview."
    : code;
  return createPluginError(code, {
    status: status,
    message: message || fallbackMessage,
    url: url
  });
}

function checkResponse(response, options) {
  if (!response) {
    throw httpError(500, options && options.message);
  }
  if (response.ok || (options && options.search && response.status === 404)) {
    return response;
  }
  throw httpError(response.status, options && options.message, response.url);
}

function isChallengeHtml(html) {
  if (!html) return false;
  var lower = String(html).toLowerCase();
  return lower.includes("cloudflare") && (lower.includes("cf-browser-verification") || lower.includes("ray id") || lower.includes("challenge-running"));
}

function assertNoChallenge(html, url) {
  if (isChallengeHtml(html)) {
    throw createPluginError(PluginError.Cloudflare, { url: url });
  }
}

function isPluginError(error) {
  return !!(error && error.name === "PluginError");
}

class Storage {
  constructor(pluginId) {
    this.pluginId = pluginId || "default";
    this._map = {};
  }
  get(key, raw) {
    var item = this._map[key];
    if (item && item.expires && Date.now() > item.expires) {
      delete this._map[key];
      return undefined;
    }
    if (!item) return undefined;
    return raw ? item : item.value;
  }
  set(key, value, expires) {
    var exp = expires instanceof Date ? expires.getTime() : (typeof expires === "number" ? expires : undefined);
    this._map[key] = {
      created: new Date(),
      value: value,
      expires: exp
    };
  }
  delete(key) {
    delete this._map[key];
  }
  clearAll() {
    this._map = {};
  }
  getAllKeys() {
    return Object.keys(this._map);
  }
}

class LocalStorage extends Storage {}
class SessionStorage extends Storage {}

function utf8ToBytes(str) {
  return new TextEncoder().encode(str);
}
function bytesToUtf8(bytes) {
  return new TextDecoder().decode(bytes);
}

const gcm = function() {
  return {
    encrypt: function() { return new Uint8Array(0); },
    decrypt: function() { return new Uint8Array(0); }
  };
};
''');
  }
}
