// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      AC: Function.prototype.call.bind(DataView.prototype.setInt32),
      AD: x0 => x0.maxTouchPoints,
      AE: (x0,x1) => x0.removeProperty(x1),
      AF: (x0,x1) => { x0.noValidate = x1 },
      AG: x0 => x0.offsetY,
      AH: x0 => x0.height,
      AI: x0 => x0.pause(),
      AJ: x0 => x0.mark,
      AK: (x0,x1,x2,x3,x4,x5) => x0.vertexAttribIPointer(x1,x2,x3,x4,x5),
      AL: x0 => x0.length,
      B: s => printToConsole(s),
      BB: x0 => x0.flags,
      BC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      BD: x0 => x0.platform,
      BE: (x0,x1) => x0.appendChild(x1),
      BF: (x0,x1) => x0.removeAttribute(x1),
      BG: x0 => x0.offsetX,
      BH: x0 => x0.clientHeight,
      BI: x0 => x0.play(),
      BJ: x0 => x0.measure,
      BK: (x0,x1,x2) => x0.vertexAttribDivisor(x1,x2),
      BL: x0 => x0.getReader(),
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      CC: o => o instanceof Uint16Array,
      CD: x0 => x0.navigator,
      CE: x0 => x0.debugShowSemanticsNodes,
      CF: x0 => x0.isConnected,
      CG: x0 => x0.type,
      CH: x0 => x0.innerWidth,
      CI: x0 => x0.paused,
      CJ: () => globalThis.performance,
      CK: (x0,x1,x2,x3,x4,x5) => x0.drawElementsInstanced(x1,x2,x3,x4,x5),
      CL: x0 => x0.value,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: o => o instanceof RegExp,
      DC: Function.prototype.call.bind(DataView.prototype.getUint16),
      DD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      DE: (o, c) => o instanceof c,
      DF: x0 => x0.click(),
      DG: x0 => x0.hasFocus(),
      DH: x0 => x0.width,
      DI: (x0,x1) => { x0.playbackRate = x1 },
      DJ: x0 => x0.createFramebuffer(),
      DK: (x0,x1,x2,x3,x4) => x0.drawElements(x1,x2,x3,x4),
      DL: x0 => x0.done,
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: (a, i, v) => a[i] = v,
      EC: Function.prototype.call.bind(DataView.prototype.setUint16),
      ED: Date.now,
      EE: x0 => x0.vendor,
      EF: (x0,x1) => x0.getElementsByClassName(x1),
      EG: x0 => x0.shiftKey,
      EH: x0 => x0.clientWidth,
      EI: (x0,x1) => { x0.volume = x1 },
      EJ: (x0,x1,x2) => x0.bindFramebuffer(x1,x2),
      EK: (x0,x1) => x0.depthFunc(x1),
      EL: x0 => x0.read(),
      F: () => new Error().stack,
      FB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      FC: o => o instanceof Int16Array,
      FD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      FE: (x0,x1) => x0.createTextNode(x1),
      FF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      FG: x0 => x0.visibilityState,
      FH: (x0,x1) => x0.removeChild(x1),
      FI: (x0,x1) => { x0.loop = x1 },
      FJ: (x0,x1,x2,x3,x4,x5) => x0.framebufferTexture2D(x1,x2,x3,x4,x5),
      FK: (x0,x1,x2,x3,x4) => x0.scissor(x1,x2,x3,x4),
      FL: x0 => x0.body,
      G: s => JSON.stringify(s),
      GB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      GC: Function.prototype.call.bind(DataView.prototype.getInt16),
      GD: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      GE: (x0,x1) => { x0.nonce = x1 },
      GF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      GG: x0 => x0.disconnect(),
      GH: x0 => x0.firstChild,
      GI: (x0,x1) => { x0.currentTime = x1 },
      GJ: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10) => x0.blitFramebuffer(x1,x2,x3,x4,x5,x6,x7,x8,x9,x10),
      GK: (x0,x1,x2) => x0.blendEquationSeparate(x1,x2),
      GL: (x0,x1) => new OffscreenCanvas(x0,x1),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      HC: Function.prototype.call.bind(DataView.prototype.setInt16),
      HD: x0 => x0.style,
      HE: x0 => x0.nonce,
      HF: (x0,x1) => x0.contains(x1),
      HG: x0 => new Intl.Locale(x0),
      HH: x0 => x0.viewConstraints,
      HI: x0 => ({cache: x0}),
      HJ: (x0,x1) => x0.deleteFramebuffer(x1),
      HK: (x0,x1,x2,x3,x4) => x0.blendFuncSeparate(x1,x2,x3,x4),
      HL: x0 => x0.assetBase,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: Function.prototype.call.bind(String.prototype.toLowerCase),
      IC: o => o instanceof Uint8ClampedArray,
      ID: (x0,x1) => x0.createElement(x1),
      IE: () => globalThis.window.flutterConfiguration,
      IF: (s) => +s,
      IG: x0 => x0.region,
      IH: x0 => x0.hostElement,
      II: (x0,x1,x2) => x0.fetch(x1,x2),
      IJ: (x0,x1,x2,x3) => x0.texParameterf(x1,x2,x3),
      IK: (x0,x1,x2) => x0.depthRange(x1,x2),
      IL: x0 => x0.loader,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      JC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      JD: x0 => x0.body,
      JE: (x0,x1) => x0.attachShadow(x1),
      JF: x0 => x0.target,
      JG: x0 => x0.script,
      JH: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      JI: x0 => x0.arrayBuffer(),
      JJ: (x0,x1,x2,x3,x4,x5) => x0.bindBufferRange(x1,x2,x3,x4,x5),
      JK: (x0,x1,x2,x3,x4) => x0.stencilFuncSeparate(x1,x2,x3,x4),
      JL: () => globalThis._flutter,
      K: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      KB: () => ({}),
      KC: Function.prototype.call.bind(DataView.prototype.setInt8),
      KD: x0 => x0.remove(),
      KE: x0 => x0.preventDefault(),
      KF: (x0,x1) => x0.dispatchEvent(x1),
      KG: x0 => x0.language,
      KH: x0 => ({runApp: x0}),
      KI: x0 => x0.status,
      KJ: (x0,x1,x2,x3,x4,x5) => x0.uniformMatrix4fv(x1,x2,x3,x4,x5),
      KK: (x0,x1,x2,x3,x4) => x0.stencilOpSeparate(x1,x2,x3,x4),
      L: o => o === undefined,
      LB: (o, p, v) => o[p] = v,
      LC: Function.prototype.call.bind(DataView.prototype.getInt8),
      LD: (x0,x1) => x0.getPropertyValue(x1),
      LE: (x0,x1) => x0.contains(x1),
      LF: (x0,x1) => x0.createEvent(x1),
      LG: x0 => x0.languages,
      LH: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      LI: x0 => x0.ok,
      LJ: (x0,x1,x2,x3,x4,x5) => x0.uniformMatrix2fv(x1,x2,x3,x4,x5),
      LK: (x0,x1,x2) => x0.stencilMaskSeparate(x1,x2),
      M: o => String(o),
      MB: () => [],
      MC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      MD: (x0,x1) => x0.warn(x1),
      ME: (x0,x1) => x0.focus(x1),
      MF: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      MG: (x0,x1) => x0.observe(x1),
      MH: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      MI: () => globalThis.window,
      MJ: (x0,x1,x2,x3,x4,x5) => x0.uniformMatrix3fv(x1,x2,x3,x4,x5),
      MK: x0 => x0.transferToImageBitmap(),
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: (a, i) => a.push(i),
      NC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      ND: x0 => x0.console,
      NE: (x0,x1) => x0.closest(x1),
      NF: () => globalThis.window,
      NG: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      NH: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      NI: (x0,x1) => x0.createShader(x1),
      NJ: (x0,x1,x2,x3,x4) => x0.uniform1fv(x1,x2,x3,x4),
      NK: x0 => x0.height,
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: b => !!b,
      OC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      OD: (x0,x1) => { x0.id = x1 },
      OE: (x0,x1) => x0.getAttribute(x1),
      OF: x0 => x0.readText(),
      OG: x0 => new ResizeObserver(x0),
      OH: () => typeof dartUseDateNowForTicks !== "undefined",
      OI: (x0,x1,x2) => x0.shaderSource(x1,x2),
      OJ: (x0,x1,x2,x3,x4) => x0.uniform2fv(x1,x2,x3,x4),
      OK: x0 => x0.width,
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: x0 => new Int8Array(x0),
      PC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      PD: s => s.trimLeft(),
      PE: x0 => x0.activeElement,
      PF: x0 => x0.clipboard,
      PG: x0 => globalThis.parseFloat(x0),
      PH: () => Date.now(),
      PI: (x0,x1) => x0.compileShader(x1),
      PJ: (x0,x1,x2,x3,x4) => x0.uniform3fv(x1,x2,x3,x4),
      PK: (x0,x1) => { x0.height = x1 },
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      QC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      QD: x0 => x0.unicode,
      QE: (x0,x1) => x0.add(x1),
      QF: (x0,x1) => x0.writeText(x1),
      QG: (x0,x1) => x0.getComputedStyle(x1),
      QH: () => 1000 * performance.now(),
      QI: (x0,x1,x2) => x0.getShaderParameter(x1,x2),
      QJ: (x0,x1,x2,x3,x4) => x0.uniform4fv(x1,x2,x3,x4),
      QK: x0 => x0.height,
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: x0 => new Uint8Array(x0),
      RC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      RD: x0 => x0.index,
      RE: x0 => x0.classList,
      RF: x0 => x0.unlock(),
      RG: x0 => x0.documentElement,
      RH: x0 => new Uint8Array(x0),
      RI: (x0,x1) => x0.getShaderInfoLog(x1),
      RJ: (x0,x1) => x0.useProgram(x1),
      RK: (x0,x1) => { x0.width = x1 },
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: x0 => new Uint8ClampedArray(x0),
      SC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      SD: (x0,x1) => x0[x1],
      SE: x0 => x0.data,
      SF: (x0,x1) => x0.lock(x1),
      SG: x0 => x0.computedStyleMap(),
      SH: (x0,x1,x2) => x0.slice(x1,x2),
      SI: (x0,x1) => x0.deleteShader(x1),
      SJ: (x0,x1,x2,x3) => x0.bindBufferBase(x1,x2,x3),
      SK: x0 => x0.width,
      T: x0 => new Promise(x0),
      TB: x0 => new Int16Array(x0),
      TC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      TD: (x0,x1) => x0.exec(x1),
      TE: x0 => x0.scrollTop,
      TF: x0 => x0.orientation,
      TG: (x0,x1) => x0.get(x1),
      TH: (x0,x1) => x0.decode(x1),
      TI: (x0,x1) => new OffscreenCanvas(x0,x1),
      TJ: (x0,x1) => x0.deleteProgram(x1),
      TK: (x0,x1,x2) => x0.insertBefore(x1,x2),
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: x0 => new Uint16Array(x0),
      UC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      UD: (x0,x1) => { x0.lastIndex = x1 },
      UE: (handle) => clearTimeout(handle),
      UF: (x0,x1) => x0.querySelector(x1),
      UG: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      UH: (x0,x1) => x0.adoptText(x1),
      UI: (x0,x1,x2,x3,x4) => ({alpha: x0,depth: x1,stencil: x2,antialias: x3,preserveDrawingBuffer: x4}),
      UJ: x0 => x0.createProgram(),
      UK: x0 => x0.id,
      V: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      VB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      VC: x0 => x0.history,
      VD: x0 => x0.dotAll,
      VE: (x0,x1) => { x0.scrollTop = x1 },
      VF: (x0,x1) => { x0.content = x1 },
      VG: x0 => x0.matches,
      VH: x0 => x0.first(),
      VI: (x0,x1,x2) => x0.getContext(x1,x2),
      VJ: (x0,x1,x2) => x0.attachShader(x1,x2),
      VK: x0 => x0.offsetHeight,
      W: x0 => new Array(x0),
      WB: x0 => new Int32Array(x0),
      WC: x0 => x0.search,
      WD: x0 => x0.ignoreCase,
      WE: x0 => x0.tagName,
      WF: x0 => x0.head,
      WG: (x0,x1) => x0.matchMedia(x1),
      WH: x0 => x0.next(),
      WI: (x0,x1) => x0.getExtension(x1),
      WJ: (x0,x1,x2,x3) => x0.bindAttribLocation(x1,x2,x3),
      WK: x0 => x0.offsetWidth,
      X: o => [o],
      XB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      XC: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      XD: x0 => x0.multiline,
      XE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      XF: (x0,x1) => { x0.name = x1 },
      XG: x0 => x0.matches,
      XH: x0 => x0.current(),
      XI: (x0,x1,x2) => x0.clipControlEXT(x1,x2),
      XJ: (x0,x1) => x0.linkProgram(x1),
      XK: x0 => x0.stopPropagation(),
      Y: (o0, o1) => [o0, o1],
      YB: x0 => new Uint32Array(x0),
      YC: x0 => x0.location,
      YD: (o, p, r) => o.replace(p, () => r),
      YE: (x0,x1) => { x0.value = x1 },
      YF: (x0,x1) => { x0.title = x1 },
      YG: x0 => x0.timeStamp,
      YH: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      YI: (x0,x1) => x0.getParameter(x1),
      YJ: (x0,x1,x2) => x0.getProgramParameter(x1,x2),
      YK: x0 => x0.disabled,
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: x0 => new Float32Array(x0),
      ZC: x0 => x0.pathname,
      ZD: (o, p, r) => o.replaceAll(p, () => r),
      ZE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      ZF: () => globalThis.document,
      ZG: (x0,x1) => x0.hasAttribute(x1),
      ZH: x0 => x0.v8BreakIterator,
      ZI: (o, t) => typeof o === t,
      ZJ: (x0,x1) => x0.getProgramInfoLog(x1),
      ZK: (x0,x1) => { x0.min = x1 },
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      aC: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      aD: x0 => x0.length,
      aE: (x0,x1) => { x0.value = x1 },
      aF: (x0,x1) => x0.vibrate(x1),
      aG: x0 => x0.buttons,
      aH: () => globalThis.Intl,
      aI: (x0,x1,x2) => x0.bindBuffer(x1,x2),
      aJ: (x0,x1,x2) => x0.getUniformLocation(x1,x2),
      aK: (x0,x1) => { x0.max = x1 },
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: x0 => new Float64Array(x0),
      bC: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      bD: s => s.trim(),
      bE: x0 => x0.relatedTarget,
      bF: (o, p) => p in o,
      bG: x0 => x0.ctrlKey,
      bH: (x0,x1) => x0.segment(x1),
      bI: (x0,x1,x2,x3) => x0.bufferSubData(x1,x2,x3),
      bJ: (x0,x1,x2) => x0.uniform1f(x1,x2),
      bK: (x0,x1) => { x0.disabled = x1 },
      c: o => o,
      cB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      cC: o => Object.keys(o),
      cD: (a, s) => a.join(s),
      cE: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      cF: x0 => x0.arrayBuffer(),
      cG: x0 => x0.y,
      cH: x0 => x0.index,
      cI: (x0,x1) => x0.bindVertexArray(x1),
      cJ: (x0,x1,x2) => x0.getUniformBlockIndex(x1,x2),
      cK: (x0,x1) => { x0.scrollLeft = x1 },
      d: (o, p) => o[p],
      dB: x0 => new ArrayBuffer(x0),
      dC: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      dD: (x0,x1) => x0.error(x1),
      dE: x0 => x0.value,
      dF: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      dG: x0 => x0.x,
      dH: x0 => x0.next(),
      dI: x0 => x0.createBuffer(),
      dJ: (x0,x1,x2,x3) => x0.uniformBlockBinding(x1,x2,x3),
      dK: (x0,x1) => { x0.spellcheck = x1 },
      e: () => globalThis,
      eB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      eC: f => f.dartFunction,
      eD: () => globalThis.console,
      eE: x0 => x0.selectionDirection,
      eF: x0 => x0.status,
      eG: x0 => x0.offsetTop,
      eH: x0 => x0.value,
      eI: (x0,x1,x2,x3) => x0.bufferData(x1,x2,x3),
      eJ: (x0,x1,x2,x3) => x0.getActiveUniformBlockParameter(x1,x2,x3),
      eK: (x0,x1) => { x0.disabled = x1 },
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: (x0,x1,x2) => new DataView(x0,x1,x2),
      fC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fD: s => s.trimRight(),
      fE: x0 => x0.selectionStart,
      fF: (x0,x1) => x0.fetch(x1),
      fG: x0 => x0.scrollLeft,
      fH: x0 => x0.done,
      fI: (x0,x1,x2,x3,x4,x5,x6,x7,x8) => x0.compressedTexSubImage2D(x1,x2,x3,x4,x5,x6,x7,x8),
      fJ: (x0,x1,x2) => x0.uniform1i(x1,x2),
      fK: x0 => x0.debugSkipFontRetryDelay,
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: (o, p) => o[p],
      gC: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      gD: (x0,x1) => x0.requestAnimationFrame(x1),
      gE: x0 => x0.selectionEnd,
      gF: x0 => x0.content,
      gG: x0 => x0.offsetLeft,
      gH: (o, m, a) => o[m].apply(o, a),
      gI: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9) => x0.texSubImage2D(x1,x2,x3,x4,x5,x6,x7,x8,x9),
      gJ: (x0,x1) => x0.disable(x1),
      gK: (x0,x1,x2) => x0.set(x1,x2),
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      hC: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      hD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      hE: x0 => x0.value,
      hF: x0 => x0.document,
      hG: x0 => x0.offsetParent,
      hH: x0 => x0.iterator,
      hI: (x0,x1) => x0.activeTexture(x1),
      hJ: (x0,x1) => x0.enable(x1),
      hK: x0 => x0.fontFallbackBaseUrl,
      i: (string, token) => string.split(token),
      iB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      iC: (o, i) => o[i],
      iD: x0 => x0.now(),
      iE: x0 => x0.selectionDirection,
      iF: x0 => x0.language,
      iG: x0 => x0.deltaMode,
      iH: () => globalThis.Symbol,
      iI: (x0,x1,x2) => x0.bindTexture(x1,x2),
      iJ: (x0,x1) => x0.cullFace(x1),
      iK: (x0,x1) => x0.transferFromImageBitmap(x1),
      j: o => o instanceof Array,
      jB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      jC: o => o.length,
      jD: x0 => x0.performance,
      jE: x0 => x0.selectionStart,
      jF: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      jG: x0 => x0.deltaY,
      jH: (x0,x1) => new Intl.Segmenter(x0,x1),
      jI: x0 => x0.createTexture(),
      jJ: (x0,x1) => x0.frontFace(x1),
      jK: (x0,x1) => x0.getContext(x1),
      k: (a, i) => a[i],
      kB: o => o.byteOffset,
      kC: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      kD: (x0,x1) => x0.unregister(x1),
      kE: x0 => x0.selectionEnd,
      kF: (x0,x1) => x0.prepend(x1),
      kG: x0 => x0.deltaX,
      kH: x0 => x0.Segmenter,
      kI: (x0,x1,x2,x3,x4,x5) => x0.texStorage2D(x1,x2,x3,x4,x5),
      kJ: (x0,x1,x2,x3,x4) => x0.clearColor(x1,x2,x3,x4),
      kK: (x0,x1) => { x0.height = x1 },
      l: a => a.length,
      lB: o => o.buffer,
      lC: x0 => x0.state,
      lD: () => globalThis.window.FinalizationRegistry,
      lE: x0 => x0.keyCode,
      lF: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      lG: x0 => x0.wheelDeltaY,
      lH: x0 => x0.buffer,
      lI: (x0,x1,x2,x3) => x0.texParameteri(x1,x2,x3),
      lJ: (x0,x1) => x0.depthMask(x1),
      lK: (x0,x1) => { x0.width = x1 },
      m: (string, times) => string.repeat(times),
      mB: (b, o) => new DataView(b, o),
      mC: x0 => x0.hash,
      mD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      mE: (x0,x1) => x0.scrollIntoView(x1),
      mF: (x0,x1) => x0.querySelector(x1),
      mG: x0 => x0.wheelDeltaX,
      mH: x0 => x0.wasmMemory,
      mI: x0 => x0.createRenderbuffer(),
      mJ: (x0,x1) => x0.clearDepth(x1),
      mK: x0 => x0.rasterEndMilliseconds,
      n: (decoder, codeUnits) => decoder.decode(codeUnits),
      nB: (b, o, l) => new DataView(b, o, l),
      nC: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      nD: x0 => new window.FinalizationRegistry(x0),
      nE: x0 => x0.multiViewEnabled,
      nF: (x0,x1) => x0.querySelectorAll(x1),
      nG: x0 => x0.key,
      nH: () => globalThis.window._flutter_skwasmInstance,
      nI: (x0,x1,x2) => x0.bindRenderbuffer(x1,x2),
      nJ: (x0,x1) => x0.stencilMask(x1),
      nK: x0 => x0.rasterStartMilliseconds,
      o: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      oB: Function.prototype.call.bind(DataView.prototype.getUint8),
      oC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      oD: x0 => x0.scale,
      oE: x0 => x0.parent,
      oF: x0 => x0.tabIndex,
      oG: x0 => x0.identifier,
      oH: () => new TextDecoder(),
      oI: (x0,x1,x2,x3,x4,x5) => x0.renderbufferStorageMultisample(x1,x2,x3,x4,x5),
      oJ: (x0,x1) => x0.clearStencil(x1),
      oK: x0 => x0.imageBitmaps,
      p: () => new TextDecoder("utf-8", {fatal: true}),
      pB: Function.prototype.call.bind(DataView.prototype.setUint8),
      pC: x0 => x0.state,
      pD: x0 => x0.visualViewport,
      pE: (x0,x1) => x0.replaceWith(x1),
      pF: x0 => x0.parentNode,
      pG: x0 => x0.touches,
      pH: (a, i) => a.splice(i, 1),
      pI: x0 => new Audio(x0),
      pJ: (x0,x1) => x0.clear(x1),
      pK: x0 => x0.canvasKitMaximumSurfaces,
      q: () => new TextDecoder("utf-8", {fatal: false}),
      qB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      qC: (x0,x1,x2) => x0.addEventListener(x1,x2),
      qD: x0 => x0.devicePixelRatio,
      qE: (x0,x1) => { x0.type = x1 },
      qF: x0 => x0.clientY,
      qG: x0 => x0.pressure,
      qH: a => a.pop(),
      qI: x0 => x0.pop(),
      qJ: (x0,x1,x2,x3,x4) => x0.viewport(x1,x2,x3,x4),
      qK: x0 => x0.hostElement,
      r: (l, r) => l === r,
      rB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      rC: (x0,x1) => x0.go(x1),
      rD: (d, digits) => d.toFixed(digits),
      rE: (x0,x1) => { x0.className = x1 },
      rF: x0 => x0.clientX,
      rG: x0 => x0.tiltY,
      rH: (map, o, v) => map.set(o, v),
      rI: x0 => x0.clearMarks(),
      rJ: (x0,x1,x2,x3,x4) => x0.framebufferRenderbuffer(x1,x2,x3,x4),
      rK: x0 => x0.location,
      s: x0 => x0.random(),
      sB: (t, s) => t.set(s),
      sC: (x0,x1) => x0.append(x1),
      sD: x0 => x0.maxHeight,
      sE: (x0,x1) => { x0.tabIndex = x1 },
      sF: x0 => x0.getBoundingClientRect(),
      sG: x0 => x0.tiltX,
      sH: (map, o) => map.get(o),
      sI: x0 => x0.clearMeasures(),
      sJ: (x0,x1) => x0.checkFramebufferStatus(x1),
      sK: (x0,x1) => x0.getModifierState(x1),
      t: o => o,
      tB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      tC: (x0,x1) => { x0.textContent = x1 },
      tD: x0 => x0.maxWidth,
      tE: (x0,x1) => { x0.name = x1 },
      tF: x0 => x0.bottom,
      tG: x0 => x0.pointerType,
      tH: () => new WeakMap(),
      tI: (x0,x1) => x0.parse(x1),
      tJ: (x0,x1,x2,x3,x4) => x0.drawArraysInstanced(x1,x2,x3,x4),
      tK: x0 => x0.metaKey,
      u: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      uB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      uC: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      uD: x0 => x0.minHeight,
      uE: (x0,x1) => { x0.placeholder = x1 },
      uF: x0 => x0.top,
      uG: x0 => x0.pointerId,
      uH: x0 => x0.close(),
      uI: (x0,x1,x2) => x0.mark(x1,x2),
      uJ: (x0,x1,x2,x3) => x0.drawArrays(x1,x2,x3),
      uK: x0 => x0.altKey,
      v: () => globalThis.Math,
      vB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      vC: x0 => x0.parentElement,
      vD: x0 => x0.minWidth,
      vE: (x0,x1) => { x0.autocomplete = x1 },
      vF: x0 => x0.right,
      vG: x0 => x0.getCoalescedEvents(),
      vH: x0 => new WeakRef(x0),
      vI: (x0,x1,x2,x3) => x0.measure(x1,x2,x3),
      vJ: (x0,x1,x2) => x0.getAttribLocation(x1,x2),
      vK: x0 => x0.ctrlKey,
      w: s => s.toUpperCase(),
      wB: Function.prototype.call.bind(DataView.prototype.getUint32),
      wC: (x0,x1) => x0.querySelectorAll(x1),
      wD: x0 => x0.height,
      wE: (x0,x1) => { x0.name = x1 },
      wF: x0 => x0.left,
      wG: (x0,x1) => x0.getModifierState(x1),
      wH: x0 => x0.deref(),
      wI: (o) => {
        const typeofValue = typeof o;
        return (typeofValue === 'object') ||
            typeofValue === 'function';
      },
      wJ: (x0,x1) => x0.enableVertexAttribArray(x1),
      wK: x0 => x0.isComposing,
      x: Object.is,
      xB: Function.prototype.call.bind(DataView.prototype.setUint32),
      xC: x0 => x0.length,
      xD: x0 => x0.width,
      xE: (x0,x1) => { x0.placeholder = x1 },
      xF: x0 => x0.clientY,
      xG: x0 => x0.blur(),
      xH: () => globalThis.WeakRef,
      xI: () => globalThis.JSON,
      xJ: (x0,x1,x2,x3,x4,x5,x6) => x0.vertexAttribPointer(x1,x2,x3,x4,x5,x6),
      xK: x0 => x0.code,
      y: (x0,x1) => x0.test(x1),
      yB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      yC: (x0,x1) => x0.item(x1),
      yD: x0 => x0.screen,
      yE: (x0,x1) => { x0.action = x1 },
      yF: x0 => x0.clientX,
      yG: x0 => x0.button,
      yH: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      yI: x0 => x0.clearMarks,
      yJ: x0 => x0.createVertexArray(),
      yK: x0 => x0.repeat,
      z: o => o,
      zB: Function.prototype.call.bind(DataView.prototype.getInt32),
      zC: x0 => x0.userAgent,
      zD: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      zE: (x0,x1) => { x0.method = x1 },
      zF: x0 => x0.changedTouches,
      zG: x0 => x0.innerHeight,
      zH: (a, s, e) => a.slice(s, e),
      zI: x0 => x0.clearMeasures,
      zJ: (x0,x1) => x0.deleteVertexArray(x1),
      zK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
