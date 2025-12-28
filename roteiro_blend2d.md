# Roteiro Portação Blend2D: C++ → Dart

**Referência**: `C:\MyDartProjects\asmjit\referencias\blend2d-master`  
**Target**: `C:\MyDartProjects\asmjit\lib\src\blend2d`  
**Objetivo**: Biblioteca gráficos 2D alta performance multiplataforma (Windows, Linux, macOS, Android, iOS)

mantenha este roteiro atualizado

**Estratégia**: Duas implementações:  
1. **JIT-acelerada** usando AsmJit (`lib/src/asmjit`)  
2. **Reference/Pure Dart** sem dependências (portátil)

**IMPORTANTE**: Manter `blend2d/`, `asmjit/`, `asmtk/` completamente separados (futuros pacotes independentes).

FOCO em PERFORMACE micro otimização é importante otimizar o maximo possivel
---

## 🧪 Status de Testes / Crash

**Data**: 27 Dezembro 2025  
**Crash**: `test/blend2d/pipeline_src_over_test.dart` (Windows x64, Dart 3.6.0)
- CRASH ao executar pipeline JIT (PC dentro do stub JIT) ao fazer load do dst pixel.
- O mesmo stub funciona quando `globalAlpha == 0` (early-return) e falha quando percorre o loop.
- Executando via Docker Linux x64: sem crash, mas divergencia em pixels e falhas de alpha.

**Falhas de testes (Linux x64/Docker)**:
- `blend2d_context_test.dart`: `BLContext globalAlpha fill` (alpha sai 0).
- `blend2d_pipeline_alpha_test.dart`: casos alpha 0.0 e 0.5 falham.

**Hipotese atual**: nao parece ser alocacao de memoria (load simples via JIT funciona), mais provavel erro de pipeline JIT/ABI/registros.

---

## 📊 Status Atual da Portação

### ✅ Implementado (baseline)

**Pipeline Backends:**
- ✅ Reference Dart (`pipeline_reference.dart`): PRGB32/XRGB32/A8, global alpha e mask
- ✅ Reference Bytes (`pipeline_reference_bytes.dart`): Uint8List/ByteData (JS compat)
- ✅ JIT X86-64 (`pipeline_compiler.dart`): copy/fill/src-over PRGB32
- ✅ JIT A64 (`pipeline_compiler.dart`): copy/fill/src-over PRGB32
- ✅ Tipos condicionais (`pipeline_types.dart`): PipelineMask (Pointer/Uint8List)

**Operações Compositing:**
- ✅ `CompOp_SrcCopy` (copy/blit)
- ✅ `CompOp_SrcOver` (sem global alpha/mask no JIT, completo na reference)
- ✅ Formula: `Dca' = Sca + Dca * (1 - Sa)`; otimizações para `Sa==0` e `Sa==255`

### 🚧 Faltando (análise do C++ original)

---

## 🗂️ Mapeamento Estrutural (C++ → Dart)

Análise de `referencias/blend2d-master/blend2d`:

### 📁 **Core** (`core/` → 134 arquivos)

Blend2D possui um vasto módulo Core com tipos fundamentais que ainda NÃO estão em `lib/src/blend2d`:

| Componente C++ | Arquivo Original | Status Dart | Prioridade |
|----------------|------------------|-------------|------------|
| **API/Globals** | `api.h` (1908 linhas) | ❌ Não portado | 🔴 Alta |
| **Array** | `array.h`, `array.cpp` | ❌ | 🟡 Média |
| **BitArray** | `bitarray.h`, `bitarray.cpp` | ❌ | 🟡 Média |
| **BitSet** | `bitset.h`, `bitset.cpp` (134 KB) | ❌ | 🟢 Baixa |
| **Context** | `context.h` (213 KB), `context.cpp` (81 KB) | ❌ | 🔴 **CRÍTICO** |
| **Font** | `font.h`, `fontface.h`, `fontdata.h` | ❌ | 🟡 Média |
| **Geometry** | `geometry.h` (paths, shapes) | ❌ | 🔴 Alta |
| **Gradient** | `gradient.h`, `gradient.cpp` | ❌ | 🔴 Alta |
| **Image** | `image.h`, `image.cpp` | ❌ | 🔴 **CRÍTICO** |
| **ImageCodec** | `imagecodec.h`, codecs (BMP/PNG/JPEG) | ❌ | 🟡 Média |
| **Matrix** | `matrix.h`, `matrix_sse2.cpp`, `matrix_avx.cpp` | ❌ | 🔴 Alta |
| **Object** | `object.h` (54 KB), `object_p.h` (ref counting) | ❌ | 🔴 **CRÍTICO** |
| **Path** | `path.h` (57 KB), `path.cpp` (84 KB) | ❌ | 🔴 **CRÍTICO** |
| **PathStroke** | `pathstroke.cpp` (33 KB) | ❌ | 🟡 Média |
| **Pattern** | `pattern.h`, `pattern.cpp` | ❌ | 🔴 Alta |
| **PixelConverter** | `pixelconverter.h`, SIMD variants | ❌ | 🟡 Média |
| **RGBA** | `rgba.h` | ❌ | 🔴 Alta |
| **Runtime** | `runtime.h`, `runtime_p.h` | ❌ | 🔴 Alta |
| **String** | `string.h`, `string.cpp` | ❌ | 🟢 Baixa |
| **Var** | `var.h` (variant type) | ❌ | 🟡 Média |

**⚠️ CRÍTICO**: `BLContext` é o componente central de rendering (213 KB de API). Sem ele, não há interface de desenho de alto nível.

---

### 📁 **Pipeline** (`pipeline/` → reference + jit)

| Componente | Arquivos C++ | Status Dart | Ação Necessária |
|------------|--------------|-------------|-----------------|
| **Reference - CompOp** | `compopgeneric_p.h` | ⚠️ Parcial | Adicionar CompOp_Plus, CompOp_Multiply, etc. |
| **Reference - Fetch** | `fetchgeneric_p.h` (40 KB) | ❌ | Portar fetchers (gradient, pattern) |
| **Reference - Fill** | `fillgeneric_p.h` (12 KB) | ❌ Parcial | Rect/span fills avançados |
| **Reference - Pixel** | `pixelgeneric_p.h` (34 KB) | ❌ | Operações pixel SIMD emuladas |

---

## ✅ Ajustes Recentes (Blend2D)

- A64 JIT: apply de constantes (width/height/stride/color) antes do emit de cada op.
- Removidos fallbacks que transformavam `globalAlpha==0` em `255` no JIT.

---

## 🧩 ARM64 / AArch64

- Dockerfile dedicado: `docker/linux-arm64-test.Dockerfile` (rodar com `--platform linux/arm64`).
- Objetivo imediato: estabilizar pipeline A64 e reproduzir testes de alpha no ARM.
| **JIT - CompOpPart** | `compoppart.cpp` (153 KB) | ❌ | Geração JIT de 30+ comp ops |
| **JIT - FetchGradient** | `fetchgradientpart.cpp` (48 KB) | ❌ | JIT de gradientes lineares/radiais/cônicos |
| **JIT - FetchPattern** | `fetchpatternpart.cpp` (80 KB) | ❌ | JIT de patterns com extend modes |
| **JIT - FetchSolid** | `fetchsolidpart.cpp` | ❌ | Fetch de cores sólidas otimizado |
| **JIT - FillPart** | `fillpart.cpp` (60 KB) | ❌ | JIT de preenchimentos analíticos |
| **JIT - PipeCompiler** | `pipecompiler.cpp`, `pipecompiler_p.h` (15 KB) | ⚠️ Básico | Expandir para full composer |
| **JIT - PipePrimitives** | `pipeprimitives_p.h` (16 KB) | ❌ | Primitivas SIMD (unpack, pack, lerp) |
| **JIT - FetchUtils** | `fetchutils*.cpp` (~200 KB total) | ❌ | Utilitários de interpolação bilinear, pixel gather |

**Pipeline Runtime:**
- `pipedefs.cpp` (25 KB): definições de formatos e flags
- `piperuntime.cpp`, `piperuntime_p.h`: dispatch dinâmico

---

### 📁 **Raster** (`raster/` → 31 arquivos)

Motor de rasterização (analítico anti-aliased):

| Componente | Arquivo C++ | Tamanho | Status |
|------------|-------------|---------|--------|
| **RasterContext** | `rastercontext.cpp` | 208 KB | ❌ **CRÍTICO** |
| **AnalyticRasterizer** | `analyticrasterizer_p.h` | 39 KB | ❌ |
| **EdgeBuilder** | `edgebuilder_p.h` | 82 KB | ❌ |
| **EdgeStorage** | `edgestorage_p.h` | 5 KB | ❌ |
| **RenderCommand** | `rendercommand*.cpp` | ~25 KB | ❌ |
| **WorkerManager** | `workermanager.cpp` | 5 KB | ❌ |

Este módulo **não existe** no port Dart atual.

---

### 📁 **Geometry** (`geometry/` → 6 arquivos)

| Arquivo | Função | Status |
|---------|---------|--------|
| `bezier_p.h` | Curvas Bézier (34 KB) | ❌ |
| `commons_p.h` | Utilitários geométricos | ❌ |
| `tolerance_p.h` | Tolerâncias de aproximação | ❌ |
| `sizetable.cpp` | Tabelas de tamanhos | ❌ |

---

### 📁 **OpenType** (`opentype/` → 29 arquivos)

Parser/layout de fontes OpenType/TrueType:

| Componente | Arquivos | Status |
|------------|----------|--------|
| **CFF Parser** | `otcff.cpp` (83 KB) | ❌ |
| **CMAP** | `otcmap.cpp` (27 KB) | ❌ |
| **GLYF (glyphs)** | `otglyf.cpp` + SIMD (76 KB total) | ❌ |
| **Kern** | `otkern.cpp` (28 KB) | ❌ |
| **Layout (GSUB/GPOS)** | `otlayout.cpp` (171 KB) | ❌ |
| **Metrics** | `otmetrics.cpp` | ❌ |
| **Name Table** | `otname.cpp` | ❌ |

---

### 📁 **Codec** (`codec/` → 10 arquivos)

Codecs de imagem:

- `bmpcodec_p.h` ❌
- `jpegcodec_p.h`, `jpegops_p.h`, `jpeghuffman_p.h` ❌
- `pngcodec_p.h`, `pngops_p.h`, SIMD impl ❌
- `qoicodec_p.h` ❌

---

### 📁 **Compression** (`compression/` → 12 arquivos)

Deflate e checksums (para PNG):

- `deflatedecoder*.cpp` ❌
- `deflateencoder*.cpp` ❌
- `checksum_p.h`, adler32/crc32 SIMD ❌

---

### 📁 **SIMD** (`simd/` → ?)

Wrappers SIMD multi-arch (SSE2, AVX2, NEON):

- Provavelmente 20+ headers
- **Estratégia Dart**: usar SIMD quando disponível via `dart:ffi` + bibliotecas nativas, ou emular na reference

---

### 📁 **Threading** (`threading/` → ?)

Multi-threading para rendering assíncrono.

---

## 🎯 Prioridades de Implementação

### **Phase 1: Core Rendering Essentials** (🔴 Crítico)

1. **BLImage** (`core/image.h/.cpp`):
   - Representação de bitmap em memória
   - Create/destroy/access pixel data
   - Formatos: PRGB32, XRGB32, A8
   
2. **BLContext** (`core/context.h/.cpp`):
   - API de desenho 2D (fill, stroke, blit)
   - Estado (transform, clip, opacity)
   - Despacho para pipeline JIT ou reference
   
3. **BLPath** (`core/path.h/.cpp`):
   - Comandos de path (moveTo, lineTo, curveTo, close)
   - Geometrias básicas (rect, circle, ellipse)
   - Transformações
   
4. **BLMatrix2D** (`core/matrix.h`):
   - Transformações afim 2D
   - Versões SIMD (AVX, SSE2) → Dart: FFI ou reference
   
5. **BLGradient** (`core/gradient.h`):
   - Linear, radial, conic gradients
   - Color stops
   
6. **BLPattern** (`core/pattern.h`):
   - Padrões baseados em imagem
   - Extend modes (pad, repeat, reflect)

### **Phase 2: Pipeline Expansion** (🟡 Alta)

7. **CompOps adicionais** (reference d primeiro, JIT depois):
   - Plus, Multiply, Screen, Overlay, Darken, Lighten...
   - ~30 modos de compositing no total
   
8. **Fetch de Gradientes** (reference):
   - Linear interpolation
   - Radial (circular/elliptical)
   - Conic (angular)
   
9. **Fetch de Patterns** (reference):
   - Affine transform sampling
   - Bilinear filtering
   - Extend modes
   
10. **JIT FetchGradientPart/FetchPatternPart**:
    - Geração de código otimizado para interpolação
    - SIMD loops (AVX2 para X86, NEON para ARM)

### **Phase 3: Rasterização** (🔴 Crítico para qualidade)

11. **AnalyticRasterizer** (`raster/analyticrasterizer_p.h`):
    - Scan conversion analítico (anti-aliasing de alta qualidade)
    - Alternativa: rasterizador scanline simples primeiro
    
12. **EdgeBuilder** (`raster/edgebuilder_p.h`):
    - Construção de listas de bordas de paths
    
13. **RasterContext** (`raster/rastercontext.cpp`):
    - Implementação concreta de BLContext para raster
    - Integração com pipeline

### **Phase 4: Fontes** (🟡 Média)

14. **BLFont/BLFontFace** (`core/font*.h`):
    - Carregamento de fontes TrueType/OpenType
    - Métricas
    
15. **OpenType Parser** (`opentype/`):
    - CMAP (Unicode → Glyph ID)
    - GLYF (contornos de glifos)
    - GSUB/GPOS (substituições e posicionamento)
    
16. **GlyphBuffer** (`core/glyphbuffer.h`):
    - Shaping de texto
    - Integração com BLContext::fillText()

### **Phase 5: Codecs e Utilitários** (🟢 Baixa prioridade)

17. **Image Codecs** (`codec/`):
    - PNG encoder/decoder (com Deflate)
    - JPEG decoder
    - BMP codec
    - QOI codec
    
18. **Containers** (`core/array.h`, `core/string.h`):
    - Substituir por equivalentes Dart (`List`, `String`)
    
19. **FileSystem** (`core/filesystem.h`):
    - Usar `dart:io` diretamente

---

## 🔍 Análise: CompOp SrcOver (Referência)

**C++ Reference** (`pipeline/reference/compopgeneric_p.h`):
```cpp
// Dca' = Sca + Dca.(1 - Sa)
// Da'  = Sa  + Da .(1 - Sa)
static BL_INLINE PixelType op_prgb32_prgb32(PixelType d, PixelType s) noexcept {
  return s + (d.unpack() * Repeat{PixelOps::Scalar::neg255(s.a())}).div255().pack();
}
```

**Dart Atual** (`pipeline_compiler.dart`):
```dart
// s + d * (255 - sa) / 255
final inv = 255 - sa;
final rb = (d & 0x00FF00FF) * inv;
final ag = ((d >> 8) & 0x00FF00FF) * inv;
// ... muldiv255 rounding ...
```

✅ **Correto**: mesma fórmula, mesma aritmética inteira 8-bit com divisão por 255.  
⚠️ **Limitações**:
- Dart JIT: Não suporta global alpha nem masks (C++ suporta via `op_prgb32_prgb32(d, s, m)`)
- Dart JIT: Não suporta A8/XRGB32 variant PATHS
- Dart Reference: ✅ Suporta alpha/masks/formatos

**Próximos Passos**:
1. Adicionar variante `_emitSrcOverWithMask()` no JIT X86/A64
2. Adicionar paths para A8 (1 byte/pixel) e XRGB32 (força alpha=255)
3. Unroll loops para widths fixos (1-4 pixels)

---

## 📋 Checklist de Implementação

### Infraestrutura Base

- [ ] `BLObjectCore` e ref-counting (`object.h`)
- [ ] `BLResult` e códigos de erro (`api.h`)
- [ ] `BLRuntime` (`runtime.h`)
- [ ] `BLVar` (variant type)

### Tipos Geométricos

- [ ] `BLPoint`, `BLPointI`
- [ ] `BLSize`, `BLSizeI`
- [ ] `BLBox`, `BLBoxI`
- [ ] `BLRect`, `BLRectI`
- [ ] `BLRoundRect`
- [ ] `BLCircle`, `BLEllipse`, `BLArc`
- [ ] `BLLine`, `BLTriangle`
- [ ] `BLPath` (commands: move, line, quad, cubic, arc, close)
- [ ] `BLMatrix2D` (affine transform)

### Styling

- [ ] `BLRgba`, `BLRgba32`, `BLRgba64`
- [ ] `BLGradient` (linear, radial, conic)
- [ ] `BLGradientStop`
- [ ] `BLPattern`

### Imaging

- [ ] `BLImage` (create, getData, formats)
- [ ] `BLImageData` (pixels, stride, format)
- [ ] `BLImageCodec`, `BLImageDecoder`, `BLImageEncoder`
- [ ] `BLPixelConverter`
- [ ] Codecs: PNG, JPEG, BMP, QOI

### Rendering Context

- [ ] `BLContext` (create, setters, begin, end)
- [ ] `BLContextCreateInfo`
- [ ] `BLContextState` (save/restore stack)
- [ ] Métodos de desenho:
  - [ ] `fillAll()`
  - [ ] `fillRect()`, `fillCircle()`, `fillPath()`
  - [ ] `strokeRect()`, `strokeCircle()`, `strokePath()`
  - [ ] `blitImage()`
  - [ ] `fillText()`, `strokeText()`
- [ ] Propriedades:
  - [ ] `setFillStyle()`, `setStrokeStyle()`
  - [ ] `setGlobalAlpha()`
  - [ ] `setCompOp()`
  - [ ] `setTransform()`, `translate()`, `rotate()`, `scale()`
  - [ ] `setClip()`
  - [ ] `setStrokeWidth()`, `setStrokeCap()`, `setStrokeJoin()`

### Pipeline (Reference)

- [ ] CompOps (30+ modos):
  - [x] SrcCopy
  - [x] SrcOver
  - [ ] SrcIn, SrcOut, SrcAtop
  - [ ] DstCopy, DstOver, DstIn, DstOut, DstAtop
  - [ ] Xor, Plus, Minus, Multiply, Screen
  - [ ] Overlay, Darken, Lighten, ColorDodge, ColorBurn
  - [ ] HardLight, SoftLight, Difference, Exclusion
- [ ] Fetch modes:
  - [ ] FetchSolid (cor sólida)
  - [ ] FetchGradient (linear, radial, conic)
  - [ ] FetchPattern (affine, bilinear)
- [ ] Fill modes:
  - [ ] FillRect (solid, gradient, pattern)
  - [ ] FillAnalytic (scan conversion com coverage)

### Pipeline (JIT)

- [ ] JIT X86:
  - [x] Copy PRGB32
  - [x] Fill PRGB32
  - [x] SrcOver PRGB32 (básico)
  - [ ] SrcOver PRGB32 + global alpha
  - [ ] SrcOver PRGB32 + mask
  - [ ] SrcOver A8, XRGB32
  - [ ] Outros CompOps (Plus, Multiply, Screen...)
  - [ ] FetchGradientPart (linear, radial)
  - [ ] FetchPatternPart
- [ ] JIT A64:
  - [x] Copy PRGB32
  - [x] Fill PRGB32
  - [x] SrcOver PRGB32 + alpha/mask
  - [ ] CompOps adicionais
  - [ ] Gradientes e patterns

### Rasterização

- [ ] EdgeBuilder (path → edges)
- [ ] AnalyticRasterizer (anti-aliasing)
- [ ] RasterContext (integration)
- [ ] WorkerManager (multi-threading opcional)

### Fontes

- [ ] `BLFont`, `BLFontFace`, `BLFontData`
- [ ] `BLFontFeatureSettings`, `BLFontVariationSettings`
- [ ] `BLGlyphBuffer` (shaping)
- [ ] `BLFontManager`
- [ ] OpenType:
  - [ ] CMAP parser
  - [ ] GLYF parser (contornos TrueType)
  - [ ] CFF parser (contornos PostScript)
  - [ ] GSUB (substituições)
  - [ ] GPOS (posicionamento)
  - [ ] Kern tables

### Otimizações e Utilitários

- [ ] PixelConverter (SIMD: SSE2, AVX2, NEON ou emulado)
- [ ] Matrix SIMD (AVX, SSE2 ou reference)
- [ ] Inline assembly helpers (via AsmJit JIT)
- [ ] Pipeline caching (cacheKey → JitFunction)
- [ ] Unroll especializado (width=1,2,3,4 pixels)
- [ ] Stride-aligned loops

---

## 🛠️ Próximos Passos Imediatos

### Curto Prazo (esta semana)

1. **BLImage básico**:
   - Criar `lib/src/blend2d/image.dart`
   - `class BLImage { Pointer<Uint8> data; int width, height, stride; BLFormat format; }`
   - `create()`, `destroy()`, `getData()`

2. **BLContext scaffold**:
   - `lib/src/blend2d/context.dart`
   - Estado mínimo (transform, fillStyle, strokeStyle)
   - `fillRect()`, `blitImage()` delegando para pipeline atual

3. **Pipeline: global alpha/mask no JIT X86**:
   - Adicionar parâmetros `globalAlpha`, `maskPtr`, `maskStride` em `_emitSrcOver()`
   - Emitir código que multiplica `Sa` por `globalAlpha` antes de blend
   - Testar com `globalAlpha=128` (50% opacity)

4. **Testes**:
   - `blend2d_image_test.dart` (create, getData)
   - `blend2d_context_test.dart` (fillRect, blitImage)
   - `blend2d_pipeline_alpha_test.dart` (global alpha correctness)

### Médio Prazo (próximas 2 semanas)

5. **BLPath**:
   - `lib/src/blend2d/path.dart`
   - `moveTo()`, `lineTo()`, `quadTo()`, `cubicTo()`, `close()`
   - `addRect()`, `addCircle()`, `addEllipse()`
   - Representação: `List<PathCmd>`, `List<double> points`

6. **BLGradient e BLPattern**:
   - `lib/src/blend2d/gradient.dart`, `pattern.dart`
   - Reference fetch implementation (scalar)

7. **RasterContext inicial**:
   - Scanline rasterizer simples (sem anti-aliasing analítico primeiro)
   - `EdgeBuilder` simplificado

8. **CompOps adicionais** (reference):
   - `CompOp_Plus`, `CompOp_Multiply`, `CompOp_Screen`

### Longo Prazo (próximos 3 meses)

9. **AnalyticRasterizer**:
   - Anti-aliasing de alta qualidade
   - Port do algoritmo C++ (~40 KB)

10. **Fontes OpenType**:
    - Parser de CMAP, GLYF
    - Shaping básico (sem GSUB/GPOS)
    - `BLContext::fillText()`

11. **JIT otimizações**:
    - FetchGradientPart (SIMD)
    - FetchPatternPart (SIMD)
    - CompOps SIMD (unpack 4 pixels, blend paralelo)

12. **Codecs**:
    - PNG decoder/encoder
    - JPEG decoder

---

## 📚 Referências Técnicas

**Composition Operators**: https://www.w3.org/TR/compositing-1/  
**Blend2D Docs**: https://blend2d.com/doc/  
**Anti-Aliasing**: "A Pixel is NOT a Little Square" (Alvy Ray Smith)  
**Scanline Rasterization**: Bresenham, Pitteway-Watkinson  

**Arquivos Críticos para Estudar**:
- `blend2d/core/context.cpp` (208 KB) - entry point do rendering
- `blend2d/raster/rastercontext.cpp` (208 KB) - implementação concreta
- `blend2d/pipeline/jit/compoppart.cpp` (153 KB) - JIT de 30+ comp ops
- `blend2d/pipeline/reference/fetchgeneric_p.h` (40 KB) - fetchers scalar

---

**Última Atualização**: 27 Dezembro 2025  
**Próxima Revisão**: Após implementar BLImage + BLContext básico
