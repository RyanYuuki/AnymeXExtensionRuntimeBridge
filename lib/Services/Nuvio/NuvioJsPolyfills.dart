class NuvioJsPolyfills {
  static const String staticPolyfillCode = '''
globalThis.SCRAPER_ID = __get_scraper_id();
globalThis.SCRAPER_SETTINGS = JSON.parse(__get_scraper_settings());
if (typeof TMDB_API_KEY === 'undefined' || !globalThis.TMDB_API_KEY) {
    globalThis.TMDB_API_KEY = __get_tmdb_api_key() || '439c478a771f35c05022f9feabcca01c';
}
if (typeof globalThis.global === 'undefined') globalThis.global = globalThis;
if (typeof globalThis.window === 'undefined') globalThis.window = globalThis;
if (typeof globalThis.self === 'undefined') globalThis.self = globalThis;

globalThis.console = globalThis.console || {};
globalThis.console.log = function() {
    var msg = Array.prototype.slice.call(arguments).map(function(a) {
        try { return (typeof a === 'object' && a !== null) ? JSON.stringify(a) : String(a); } catch (_) { return String(a); }
    }).join(' ');
    try { sendMessage('nuvio_console_log', JSON.stringify({ msg: msg })); } catch (_) {}
};
globalThis.console.error = function() {
    var msg = Array.prototype.slice.call(arguments).map(function(a) {
        try { return (typeof a === 'object' && a !== null) ? JSON.stringify(a) : String(a); } catch (_) { return String(a); }
    }).join(' ');
    try { sendMessage('nuvio_console_error', JSON.stringify({ msg: msg })); } catch (_) {}
};
globalThis.console.warn = function() {
    var msg = Array.prototype.slice.call(arguments).map(function(a) {
        try { return (typeof a === 'object' && a !== null) ? JSON.stringify(a) : String(a); } catch (_) { return String(a); }
    }).join(' ');
    try { sendMessage('nuvio_console_warn', JSON.stringify({ msg: msg })); } catch (_) {}
};
globalThis.console.info = globalThis.console.log;
globalThis.console.debug = globalThis.console.log;

if (!Promise.allSettled) {
    Promise.allSettled = function(promises) {
        return Promise.all(promises.map(function(p) {
            return Promise.resolve(p).then(
                function(val) { return { status: 'fulfilled', value: val }; },
                function(err) { return { status: 'rejected', reason: err }; }
            );
        }));
    };
}

if (!String.prototype.padStart) {
    String.prototype.padStart = function(targetLength, padString) {
        targetLength = targetLength >> 0;
        padString = String(padString !== undefined ? padString : ' ');
        if (this.length > targetLength) return String(this);
        targetLength = targetLength - this.length;
        if (targetLength > padString.length) {
            padString += padString.repeat(targetLength / padString.length);
        }
        return padString.slice(0, targetLength) + String(this);
    };
}

if (!String.prototype.padEnd) {
    String.prototype.padEnd = function(targetLength, padString) {
        targetLength = targetLength >> 0;
        padString = String(padString !== undefined ? padString : ' ');
        if (this.length > targetLength) return String(this);
        targetLength = targetLength - this.length;
        if (targetLength > padString.length) {
            padString += padString.repeat(targetLength / padString.length);
        }
        return String(this) + padString.slice(0, targetLength);
    };
}

var __plugin_timer_id = 0;
var __plugin_timers = Object.create(null);
function __plugin_delay_value(value, interval) {
    var duration = Number(value);
    if (!isFinite(duration) || duration < 0) duration = 0;
    duration = Math.min(Math.floor(duration), 60000);
    return interval && duration < 1 ? 1 : duration;
}
if (typeof globalThis.setTimeout === 'undefined') {
    globalThis.setTimeout = function(callback, delay) {
        if (typeof callback !== 'function') throw new TypeError('Timer callback must be a function');
        var id = ++__plugin_timer_id;
        var args = Array.prototype.slice.call(arguments, 2);
        __plugin_timers[id] = true;
        __plugin_sleep(__plugin_delay_value(delay, false)).then(function() {
            if (!__plugin_timers[id]) return;
            delete __plugin_timers[id];
            try { callback.apply(globalThis, args); } catch (e) {}
        }, function(error) {
            delete __plugin_timers[id];
        });
        return id;
    };
}
if (typeof globalThis.clearTimeout === 'undefined') {
    globalThis.clearTimeout = function(id) { delete __plugin_timers[id]; };
}
if (typeof globalThis.setInterval === 'undefined') {
    globalThis.setInterval = function(callback, delay) {
        if (typeof callback !== 'function') throw new TypeError('Timer callback must be a function');
        var id = ++__plugin_timer_id;
        var duration = __plugin_delay_value(delay, true);
        var args = Array.prototype.slice.call(arguments, 2);
        __plugin_timers[id] = true;
        function tick() {
            __plugin_sleep(duration).then(function() {
                if (!__plugin_timers[id]) return;
                try { callback.apply(globalThis, args); } catch (e) {}
                if (__plugin_timers[id]) tick();
            }, function(error) {
                delete __plugin_timers[id];
            });
        }
        tick();
        return id;
    };
}
if (typeof globalThis.clearInterval === 'undefined') {
    globalThis.clearInterval = function(id) { delete __plugin_timers[id]; };
}

function __normalize_fetch_headers(headers) {
    var out = {};
    if (!headers) return out;
    if (typeof headers.forEach === 'function') {
        headers.forEach(function(value, key) { out[key] = String(value); });
        return out;
    }
    if (Array.isArray(headers)) {
        headers.forEach(function(pair) {
            if (pair && pair.length >= 2) out[pair[0]] = String(pair[1]);
        });
        return out;
    }
    Object.keys(headers).forEach(function(key) { out[key] = String(headers[key]); });
    return out;
}

function __fetch_bytes_to_base64(bytes) {
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var out = '';
    for (var i = 0; i < bytes.length; i += 3) {
        var a = bytes[i];
        var hasB = i + 1 < bytes.length;
        var hasC = i + 2 < bytes.length;
        var b = hasB ? bytes[i + 1] : 0;
        var c = hasC ? bytes[i + 2] : 0;
        out += chars.charAt(a >> 2);
        out += chars.charAt(((a & 3) << 4) | (b >> 4));
        out += hasB ? chars.charAt(((b & 15) << 2) | (c >> 6)) : '=';
        out += hasC ? chars.charAt(c & 63) : '=';
    }
    return out;
}

function __fetch_base64_to_bytes(value) {
    var binary = atob(value || '');
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
}

function __normalize_fetch_body(body) {
    if (body === undefined || body === null) return { kind: 'none', value: '' };
    if (typeof body === 'string') return { kind: 'text', value: body };

    var bytes = null;
    if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) {
        bytes = new Uint8Array(body);
    } else if (typeof ArrayBuffer !== 'undefined' &&
               typeof ArrayBuffer.isView === 'function' && ArrayBuffer.isView(body)) {
        bytes = new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
    }
    if (bytes !== null) {
        return { kind: 'base64', value: __fetch_bytes_to_base64(bytes) };
    }
    return { kind: 'text', value: String(body) };
}

var fetch = async function(url, options) {
    options = options || {};
    var method = (options.method || 'GET').toUpperCase();
    var headers = __normalize_fetch_headers(options.headers);
    var body = __normalize_fetch_body(options.body);
    var followRedirects = options.redirect !== 'manual';
    var result = await __native_fetch(url, method, JSON.stringify(headers), body.kind, body.value, followRedirects);
    var parsed = JSON.parse(result);
    var responseBytes = __fetch_base64_to_bytes(parsed.bodyBase64);
    return {
        ok: parsed.ok,
        status: parsed.status,
        statusText: parsed.statusText,
        url: parsed.url,
        headers: {
            get: function(name) {
                return parsed.headers[name.toLowerCase()] || null;
            }
        },
        arrayBuffer: function() {
            var copy = new Uint8Array(responseBytes.length);
            copy.set(responseBytes);
            return Promise.resolve(copy.buffer);
        },
        text: function() { return Promise.resolve(parsed.body); },
        json: function() {
            try {
                if (parsed.body === null || parsed.body === undefined || parsed.body === '') {
                    return Promise.resolve(null);
                }
                var parsedJson = JSON.parse(parsed.body);
                if (Array.isArray(parsedJson) && parsedJson.length > 0 && typeof parsedJson[0] === 'object' && parsedJson[0] !== null) {
                    var first = parsedJson[0];
                    for (var key in first) {
                        if (first.hasOwnProperty(key) && !(key in parsedJson)) {
                            parsedJson[key] = first[key];
                        }
                    }
                    if (!('malId' in parsedJson) && first.myanimelist) parsedJson.malId = first.myanimelist;
                    if (!('aniId' in parsedJson) && first.anilist) parsedJson.aniId = first.anilist;
                }
                return Promise.resolve(parsedJson);
            } catch (e) {
                return Promise.resolve(null);
            }
        }
    };
};

if (typeof AbortSignal === 'undefined') {
    var AbortSignal = function() { this.aborted = false; this.reason = undefined; this._listeners = []; };
    AbortSignal.prototype.addEventListener = function(type, listener) {
        if (type !== 'abort' || typeof listener !== 'function') return;
        this._listeners.push(listener);
    };
    AbortSignal.prototype.removeEventListener = function(type, listener) {
        if (type !== 'abort') return;
        this._listeners = this._listeners.filter(function(l) { return l !== listener; });
    };
    AbortSignal.prototype.dispatchEvent = function(event) {
        if (!event || event.type !== 'abort') return true;
        for (var i = 0; i < this._listeners.length; i++) {
            try { this._listeners[i].call(this, event); } catch (e) {}
        }
        return true;
    };
    globalThis.AbortSignal = AbortSignal;
}

if (typeof AbortController === 'undefined') {
    var AbortController = function() { this.signal = new AbortSignal(); };
    AbortController.prototype.abort = function(reason) {
        if (this.signal.aborted) return;
        this.signal.aborted = true;
        this.signal.reason = reason;
        this.signal.dispatchEvent({ type: 'abort' });
    };
    globalThis.AbortController = AbortController;
}

if (typeof btoa === 'undefined') {
    globalThis.btoa = function(str) {
        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        var encoded = '';
        for (var i = 0; i < str.length; i += 3) {
            var c1 = str.charCodeAt(i);
            var c2 = str.charCodeAt(i + 1);
            var c3 = str.charCodeAt(i + 2);
            var e1 = c1 >> 2;
            var e2 = ((c1 & 3) << 4) | (c2 >> 4);
            var e3 = ((c2 & 15) << 2) | (c3 >> 6);
            var e4 = c3 & 63;
            if (isNaN(c2)) { e3 = e4 = 64; }
            else if (isNaN(c3)) { e4 = 64; }
            encoded += chars.charAt(e1) + chars.charAt(e2) + chars.charAt(e3) + chars.charAt(e4);
        }
        return encoded;
    };
}

if (typeof atob === 'undefined') {
    globalThis.atob = function(str) {
        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        var decoded = '';
        str = String(str).replace(/=+\$/, '');
        for (var i = 0; i < str.length; i += 4) {
            var b1 = chars.indexOf(str.charAt(i));
            var b2 = chars.indexOf(str.charAt(i + 1));
            var b3 = chars.indexOf(str.charAt(i + 2));
            var b4 = chars.indexOf(str.charAt(i + 3));
            var c1 = (b1 << 2) | (b2 >> 4);
            var c2 = ((b2 & 15) << 4) | (b3 >> 2);
            var c3 = ((b3 & 3) << 6) | b4;
            decoded += String.fromCharCode(c1);
            if (b3 !== -1 && b3 !== 64) decoded += String.fromCharCode(c2);
            if (b4 !== -1 && b4 !== 64) decoded += String.fromCharCode(c3);
        }
        return decoded;
    };
}

var URL = function(url, base) {
    var raw = __parse_url(url, base ? String(base) : '');
    var parsed = JSON.parse(raw);
    this.href = parsed.href;
    this.protocol = parsed.protocol;
    this.host = parsed.host;
    this.hostname = parsed.hostname;
    this.port = parsed.port;
    this.pathname = parsed.pathname;
    this.search = parsed.search;
    this.hash = parsed.hash;
    this.origin = parsed.origin;
    this.searchParams = new URLSearchParams(this.search);
};
URL.prototype.toString = function() {
    var s = this.searchParams.toString();
    var q = s ? ('?' + s) : '';
    var origin = this.protocol ? (this.protocol + '//' + this.host) : (this.origin || '');
    return origin + this.pathname + q + this.hash;
};
globalThis.URL = URL;

var URLSearchParams = function(init) {
    this._params = {};
    if (typeof init === 'string') {
        var str = init.charAt(0) === '?' ? init.substring(1) : init;
        if (str.length > 0) {
            var pairs = str.split('&');
            for (var i = 0; i < pairs.length; i++) {
                var idx = pairs[i].indexOf('=');
                if (idx >= 0) {
                    var k = decodeURIComponent(pairs[i].substring(0, idx));
                    var v = decodeURIComponent(pairs[i].substring(idx + 1));
                    this.set(k, v);
                } else {
                    this.set(decodeURIComponent(pairs[i]), '');
                }
            }
        }
    } else if (init && typeof init === 'object') {
        var self = this;
        Object.keys(init).forEach(function(k) { self.set(k, String(init[k])); });
    }
};
URLSearchParams.prototype.get = function(key) {
    if (!this._params.hasOwnProperty(key)) return null;
    return Array.isArray(this._params[key]) ? this._params[key][0] : this._params[key];
};
URLSearchParams.prototype.getAll = function(key) {
    if (!this._params.hasOwnProperty(key)) return [];
    return Array.isArray(this._params[key]) ? this._params[key] : [this._params[key]];
};
URLSearchParams.prototype.set = function(key, value) { this._params[key] = String(value); };
URLSearchParams.prototype.append = function(key, value) {
    if (!this._params.hasOwnProperty(key)) {
        this._params[key] = String(value);
    } else if (Array.isArray(this._params[key])) {
        this._params[key].push(String(value));
    } else {
        this._params[key] = [this._params[key], String(value)];
    }
};
URLSearchParams.prototype.has = function(key) { return this._params.hasOwnProperty(key); };
URLSearchParams.prototype.delete = function(key) { delete this._params[key]; };
URLSearchParams.prototype.keys = function() { return Object.keys(this._params); };
URLSearchParams.prototype.values = function() {
    var self = this;
    var res = [];
    Object.keys(this._params).forEach(function(k) {
        var v = self._params[k];
        if (Array.isArray(v)) res.push.apply(res, v);
        else res.push(v);
    });
    return res;
};
URLSearchParams.prototype.toString = function() {
    var self = this;
    var pairs = [];
    Object.keys(this._params).forEach(function(k) {
        var v = self._params[k];
        if (Array.isArray(v)) {
            v.forEach(function(item) { pairs.push(encodeURIComponent(k) + '=' + encodeURIComponent(item)); });
        } else {
            pairs.push(encodeURIComponent(k) + '=' + encodeURIComponent(v));
        }
    });
    return pairs.join('&');
};
URLSearchParams.prototype.entries = function() {
    var self = this;
    var list = [];
    Object.keys(this._params).forEach(function(k) {
        var v = self._params[k];
        if (Array.isArray(v)) {
            v.forEach(function(item) { list.push([k, item]); });
        } else {
            list.push([k, v]);
        }
    });
    return list;
};
URLSearchParams.prototype.forEach = function(callback) {
    var self = this;
    Object.keys(this._params).forEach(function(key) { callback(self.get(key), key, self); });
};
globalThis.URLSearchParams = URLSearchParams;

var WordArray = {
    init: function(words, sigBytes) {
        this.words = words || [];
        this.sigBytes = sigBytes != undefined ? sigBytes : this.words.length * 4;
    },
    toString: function(encoder) {
        return (encoder || CryptoJS.enc.Hex).stringify(this);
    },
    concat: function(wordArray) {
        var thisWords = this.words;
        var thatWords = wordArray.words;
        var thisSigBytes = this.sigBytes;
        var thatSigBytes = wordArray.sigBytes;
        this.clamp();
        for (var i = 0; i < thatSigBytes; i++) {
            var thatByte = (thatWords[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
            thisWords[(thisSigBytes + i) >>> 2] |= thatByte << (24 - ((thisSigBytes + i) % 4) * 8);
        }
        this.sigBytes += thatSigBytes;
        return this;
    },
    clamp: function() {
        var words = this.words;
        var sigBytes = this.sigBytes;
        if (sigBytes % 4) {
            words[sigBytes >>> 2] &= 0xffffffff << (32 - (sigBytes % 4) * 8);
        }
        words.length = Math.ceil(sigBytes / 4);
        return this;
    },
    clone: function() {
        return __wordArrayCreate(this.words.slice(0), this.sigBytes);
    }
};

function __wordArrayCreate(words, sigBytes) {
    var wa = Object.create(WordArray);
    wa.init(words, sigBytes);
    return wa;
}

function __isWordArray(value) {
    return value && typeof value === 'object' && Array.isArray(value.words) && typeof value.sigBytes === 'number';
}

function __toUint8Array(data) {
    if (!data) return new Uint8Array(0);
    if (data instanceof Uint8Array) return data;
    if (data instanceof ArrayBuffer) return new Uint8Array(data);
    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(data)) {
        return new Uint8Array(data.buffer, data.byteOffset || 0, data.byteLength);
    }
    if (Array.isArray(data)) return new Uint8Array(data);
    return new Uint8Array(0);
}

function __wordArrayToBytes(wordArray) {
    if (!__isWordArray(wordArray)) return typeof wordArray === 'string' ? new TextEncoder().encode(wordArray) : __toUint8Array(wordArray);
    var bytes = new Uint8Array(wordArray.sigBytes);
    for (var i = 0; i < wordArray.sigBytes; i++) {
        bytes[i] = (wordArray.words[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
    }
    return bytes;
}

function __bytesToWordArray(bytes) {
    bytes = __toUint8Array(bytes);
    var words = [];
    for (var i = 0; i < bytes.length; i++) {
        words[i >>> 2] |= (bytes[i] & 0xff) << (24 - (i % 4) * 8);
    }
    return __wordArrayCreate(words, bytes.length);
}

function __bytesToHex(bytes) {
    bytes = __toUint8Array(bytes);
    var out = [];
    for (var i = 0; i < bytes.length; i++) {
        var hex = bytes[i].toString(16);
        out.push(hex.length < 2 ? '0' + hex : hex);
    }
    return out.join('');
}

function __hexToBytes(hex) {
    hex = String(hex || '').replace(/[^0-9a-fA-F]/g, '');
    if (hex.length % 2) hex = '0' + hex;
    var bytes = new Uint8Array(hex.length / 2);
    for (var i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substr(i, 2), 16) & 0xff;
    }
    return bytes;
}

function __evpKdf(passwordBytes, saltBytes, keySizeBytes, ivSizeBytes) {
    var targetSize = keySizeBytes + ivSizeBytes;
    var derived = new Uint8Array(targetSize);
    var block = new Uint8Array(0);
    var offset = 0;
    while (offset < targetSize) {
        var total = block.length + passwordBytes.length + saltBytes.length;
        var input = new Uint8Array(total);
        input.set(block, 0);
        input.set(passwordBytes, block.length);
        input.set(saltBytes, block.length + passwordBytes.length);
        var hashHex = __crypto_digest_hex_raw('MD5', __bytesToHex(input));
        block = __hexToBytes(hashHex);
        var copyLen = Math.min(block.length, targetSize - offset);
        derived.set(block.subarray(0, copyLen), offset);
        offset += copyLen;
    }
    return {
        key: derived.subarray(0, keySizeBytes),
        iv: derived.subarray(keySizeBytes, targetSize)
    };
}

var CryptoJS = {
    lib: {
        WordArray: {
            create: __wordArrayCreate,
            random: function(nBytes) {
                var raw = __crypto_get_random_values_hex(nBytes);
                return __bytesToWordArray(__hexToBytes(raw));
            }
        },
        CipherParams: {
            create: function(obj) { return obj || {}; }
        }
    },
    mode: {
        CTR: 'CTR',
        CBC: 'CBC',
        ECB: 'ECB',
        GCM: 'GCM'
    },
    pad: {
        NoPadding: 'NoPadding',
        Pkcs7: 'Pkcs7',
        ZeroPadding: 'ZeroPadding'
    },
    enc: {
        Hex: {
            stringify: function(wordArray) { return __bytesToHex(__wordArrayToBytes(wordArray)); },
            parse: function(hexStr) { return __bytesToWordArray(__hexToBytes(hexStr)); }
        },
        Utf8: {
            stringify: function(wordArray) { return __crypto_hex_to_utf8(__bytesToHex(__wordArrayToBytes(wordArray))); },
            parse: function(utf8Str) { return __bytesToWordArray(__hexToBytes(__crypto_utf8_to_hex(utf8Str))); }
        },
        Base64: {
            stringify: function(wordArray) { return btoa(String.fromCharCode.apply(null, __wordArrayToBytes(wordArray))); },
            parse: function(base64Str) {
                var bin = atob(base64Str);
                var bytes = new Uint8Array(bin.length);
                for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
                return __bytesToWordArray(bytes);
            }
        }
    },
    MD5: function(m) { return __bytesToWordArray(__hexToBytes(__crypto_digest_hex_raw('MD5', __bytesToHex(__wordArrayToBytes(m))))); },
    SHA1: function(m) { return __bytesToWordArray(__hexToBytes(__crypto_digest_hex_raw('SHA1', __bytesToHex(__wordArrayToBytes(m))))); },
    SHA256: function(m) { return __bytesToWordArray(__hexToBytes(__crypto_digest_hex_raw('SHA256', __bytesToHex(__wordArrayToBytes(m))))); },
    HmacMD5: function(m, k) { return __bytesToWordArray(__hexToBytes(__crypto_hmac_hex_raw('MD5', __bytesToHex(__wordArrayToBytes(k)), __bytesToHex(__wordArrayToBytes(m))))); },
    HmacSHA1: function(m, k) { return __bytesToWordArray(__hexToBytes(__crypto_hmac_hex_raw('SHA1', __bytesToHex(__wordArrayToBytes(k)), __bytesToHex(__wordArrayToBytes(m))))); },
    HmacSHA256: function(m, k) { return __bytesToWordArray(__hexToBytes(__crypto_hmac_hex_raw('SHA256', __bytesToHex(__wordArrayToBytes(k)), __bytesToHex(__wordArrayToBytes(m))))); },
    HmacSHA512: function(m, k) { return __bytesToWordArray(__hexToBytes(__crypto_hmac_hex_raw('SHA512', __bytesToHex(__wordArrayToBytes(k)), __bytesToHex(__wordArrayToBytes(m))))); },
    PBKDF2: function(pass, salt, options) {
        options = options || {};
        var pBytes = __wordArrayToBytes(pass);
        var sBytes = __wordArrayToBytes(salt);
        var iter = options.iterations || 1000;
        var kSize = options.keySize || 8;
        var algo = options.hasher || 'SHA1';
        var hex = __crypto_pbkdf2_hex(__bytesToHex(pBytes), __bytesToHex(sBytes), iter, kSize * 32, algo);
        return __bytesToWordArray(__hexToBytes(hex));
    },
    AES: {
        encrypt: function(message, key, options) {
            options = options || {};
            var data = __wordArrayToBytes(message);
            var kBytes;
            var ivBytes;
            var isPassphrase = typeof key === 'string';
            if (isPassphrase) {
                var saltBytes = options.salt ? __wordArrayToBytes(options.salt) : __hexToBytes(__crypto_get_random_values_hex(8));
                var derived = __evpKdf(new TextEncoder().encode(key), saltBytes, 32, 16);
                kBytes = derived.key;
                ivBytes = options.iv ? __wordArrayToBytes(options.iv) : derived.iv;
            } else {
                kBytes = __wordArrayToBytes(key);
                ivBytes = options.iv ? __wordArrayToBytes(options.iv) : new Uint8Array(0);
            }
            var mode = typeof options.mode === 'string' ? options.mode : (options.mode ? (options.mode.name || 'AES-CTR') : 'AES-CBC');
            var resHex = __crypto_aes_encrypt_hex(mode, __bytesToHex(kBytes), __bytesToHex(ivBytes), __bytesToHex(data));
            var ct = __bytesToWordArray(__hexToBytes(resHex));
            return {
                ciphertext: ct,
                toString: function() { return CryptoJS.enc.Base64.stringify(ct); }
            };
        },
        decrypt: function(cipher, key, options) {
            options = options || {};
            var ctBytes;
            if (typeof cipher === 'string') {
                ctBytes = __wordArrayToBytes(CryptoJS.enc.Base64.parse(cipher));
            } else if (cipher.ciphertext) {
                ctBytes = __wordArrayToBytes(cipher.ciphertext);
            } else {
                ctBytes = __wordArrayToBytes(cipher);
            }
            var kBytes;
            var ivBytes;
            var isPassphrase = typeof key === 'string';
            if (isPassphrase) {
                var derived = __evpKdf(new TextEncoder().encode(key), new Uint8Array(0), 32, 16);
                kBytes = derived.key;
                ivBytes = options.iv ? __wordArrayToBytes(options.iv) : derived.iv;
            } else {
                kBytes = __wordArrayToBytes(key);
                ivBytes = options.iv ? __wordArrayToBytes(options.iv) : new Uint8Array(0);
            }
            var mode = typeof options.mode === 'string' ? options.mode : (options.mode ? (options.mode.name || 'AES-CTR') : 'AES-CBC');
            var resHex = __crypto_aes_decrypt_hex(mode, __bytesToHex(kBytes), __bytesToHex(ivBytes), __bytesToHex(ctBytes));
            return __bytesToWordArray(__hexToBytes(resHex));
        }
    }
};
globalThis.CryptoJS = CryptoJS;
CryptoJS.default = CryptoJS;

if (typeof TextEncoder === 'undefined') {
    globalThis.TextEncoder = function() {};
    TextEncoder.prototype.encode = function(str) {
        var hex = __crypto_utf8_to_hex(str);
        return __hexToBytes(hex);
    };
}
if (typeof TextDecoder === 'undefined') {
    globalThis.TextDecoder = function() {};
    TextDecoder.prototype.decode = function(data) {
        var hex = __bytesToHex(__toUint8Array(data));
        return __crypto_hex_to_utf8(hex);
    };
}

var cheerio = {
    load: function(html) {
        var docId = __cheerio_load(html);
        var \$ = function(selector, context) {
            if (selector && selector._elementIds) return selector;
            if (context && context._elementIds && context._elementIds.length > 0) {
                var allIds = [];
                for (var i = 0; i < context._elementIds.length; i++) {
                    var childIdsJson = __cheerio_find(docId, context._elementIds[i], selector);
                    allIds = allIds.concat(JSON.parse(childIdsJson));
                }
                return createCheerioWrapperFromIds(docId, allIds);
            }
            return createCheerioWrapper(docId, selector);
        };
        \$.html = function(el) {
            if (el && el._elementIds && el._elementIds.length > 0) {
                return __cheerio_html(docId, el._elementIds[0]);
            }
            return __cheerio_html(docId, '');
        };
        return \$;
    }
};

function createCheerioWrapper(docId, selector) {
    var elementIds;
    if (typeof selector === 'string') {
        var idsJson = __cheerio_select(docId, selector);
        elementIds = JSON.parse(idsJson);
    } else {
        elementIds = [];
    }
    return createCheerioWrapperFromIds(docId, elementIds);
}

function createCheerioWrapperFromIds(docId, ids) {
    var wrapper = {
        _docId: docId,
        _elementIds: ids,
        length: ids.length,
        each: function(callback) {
            for (var i = 0; i < ids.length; i++) {
                var elWrapper = createCheerioWrapperFromIds(docId, [ids[i]]);
                callback.call(elWrapper, i, elWrapper);
            }
            return wrapper;
        },
        find: function(sel) {
            var allIds = [];
            for (var i = 0; i < ids.length; i++) {
                var childIdsJson = __cheerio_find(docId, ids[i], sel);
                allIds = allIds.concat(JSON.parse(childIdsJson));
            }
            return createCheerioWrapperFromIds(docId, allIds);
        },
        text: function() {
            if (ids.length === 0) return '';
            return __cheerio_text(docId, ids.join(','));
        },
        html: function() {
            if (ids.length === 0) return '';
            return __cheerio_inner_html(docId, ids[0]);
        },
        attr: function(name) {
            if (ids.length === 0) return undefined;
            var val = __cheerio_attr(docId, ids[0], name);
            return val === '__UNDEFINED__' ? undefined : val;
        },
        first: function() { return createCheerioWrapperFromIds(docId, ids.length > 0 ? [ids[0]] : []); },
        last: function() { return createCheerioWrapperFromIds(docId, ids.length > 0 ? [ids[ids.length - 1]] : []); },
        next: function() {
            var nextIds = [];
            for (var i = 0; i < ids.length; i++) {
                var nextId = __cheerio_next(docId, ids[i]);
                if (nextId && nextId !== '__NONE__') nextIds.push(nextId);
            }
            return createCheerioWrapperFromIds(docId, nextIds);
        },
        prev: function() {
            var prevIds = [];
            for (var i = 0; i < ids.length; i++) {
                var prevId = __cheerio_prev(docId, ids[i]);
                if (prevId && prevId !== '__NONE__') prevIds.push(prevId);
            }
            return createCheerioWrapperFromIds(docId, prevIds);
        },
        eq: function(index) {
            if (index >= 0 && index < ids.length) return createCheerioWrapperFromIds(docId, [ids[index]]);
            return createCheerioWrapperFromIds(docId, []);
        },
        map: function(callback) {
            var results = [];
            for (var i = 0; i < ids.length; i++) {
                var elWrapper = createCheerioWrapperFromIds(docId, [ids[i]]);
                var result = callback.call(elWrapper, i, elWrapper);
                if (result !== undefined && result !== null) results.push(result);
            }
            return {
                length: results.length,
                get: function(index) { return typeof index === 'number' ? results[index] : results; },
                toArray: function() { return results; }
            };
        },
        filter: function(selectorOrCallback) {
            if (typeof selectorOrCallback === 'function') {
                var filteredIds = [];
                for (var i = 0; i < ids.length; i++) {
                    var elWrapper = createCheerioWrapperFromIds(docId, [ids[i]]);
                    var result = selectorOrCallback.call(elWrapper, i, elWrapper);
                    if (result) filteredIds.push(ids[i]);
                }
                return createCheerioWrapperFromIds(docId, filteredIds);
            }
            return wrapper;
        },
        get: function(index) {
            if (typeof index === 'number') {
                if (index >= 0 && index < ids.length) return createCheerioWrapperFromIds(docId, [ids[index]]);
                return undefined;
            }
            return ids.map(function(id) { return createCheerioWrapperFromIds(docId, [id]); });
        },
        parent: function() { return createCheerioWrapperFromIds(docId, []); },
        children: function(sel) { return this.find(sel || '*'); },
        toArray: function() { return ids.map(function(id) { return createCheerioWrapperFromIds(docId, [id]); }); }
    };
    return wrapper;
}

var require = function(moduleName) {
    if (moduleName === 'cheerio' || moduleName === 'cheerio-without-node-native' || moduleName === 'react-native-cheerio') {
        return cheerio;
    }
    if (moduleName === 'crypto-js') {
        return CryptoJS;
    }
    throw new Error("Module '" + moduleName + "' is not available");
};

if (!Array.prototype.flat) {
    Array.prototype.flat = function(depth) {
        depth = depth === undefined ? 1 : Math.floor(depth);
        if (depth < 1) return Array.prototype.slice.call(this);
        return (function flatten(arr, d) {
            return d > 0
                ? arr.reduce(function(acc, val) { return acc.concat(Array.isArray(val) ? flatten(val, d - 1) : val); }, [])
                : arr.slice();
        })(this, depth);
    };
}
if (!Array.prototype.flatMap) {
    Array.prototype.flatMap = function(callback, thisArg) { return this.map(callback, thisArg).flat(); };
}
if (!Object.entries) {
    Object.entries = function(obj) {
        var result = [];
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) result.push([key, obj[key]]);
        }
        return result;
    };
}
if (!Object.fromEntries) {
    Object.fromEntries = function(entries) {
        var result = {};
        for (var i = 0; i < entries.length; i++) {
            result[entries[i][0]] = entries[i][1];
        }
        return result;
    };
}
if (!String.prototype.replaceAll) {
    String.prototype.replaceAll = function(search, replace) {
        if (search instanceof RegExp) {
            if (!search.global) throw new TypeError('replaceAll must be called with a global RegExp');
            return this.replace(search, replace);
        }
        return this.split(search).join(replace);
    };
}
''';

  static const String staticCallCode = '''
(async function() {
    try {
        var getStreams = module.exports.getStreams || globalThis.getStreams;
        if (!getStreams) {
            console.error("getStreams function not found on module.exports or globalThis");
            __capture_result(JSON.stringify([]));
            return;
        }
        var args = JSON.parse(__get_call_args());
        var season = args.season == null ? undefined : args.season;
        var episode = args.episode == null ? undefined : args.episode;
        var result = await getStreams(args.tmdbId, args.mediaType, season, episode);
        __capture_result(JSON.stringify(result || []));
    } catch (e) {
        console.error("getStreams execution error: " + (e && e.stack ? e.stack : (e && e.message ? e.message : e)));
        __capture_result(JSON.stringify([]));
    }
})();
''';

  static const String staticSettingsCallCode = '''
(async function() {
    try {
        var onSettings = (typeof module !== 'undefined' && module.exports && module.exports.onSettings) || globalThis.onSettings;
        if (typeof onSettings === 'function') {
            var layout = await onSettings();
            __capture_result(JSON.stringify(layout || []));
        } else {
            __capture_result("[]");
        }
    } catch (e) {
        console.error("onSettings execution error: " + (e && e.message ? e.message : e));
        __capture_result("[]");
    }
})();
''';
}
