 tem que ir vendo arquivo por arquivo e ir corrgindo para que a logica seja identica ao c++
 
 tem que ter a mesma logica exata do c++ se não tiver a logica identica ao c++ não vai funcionar

### Status atual

- Helpers de função e frames usam agora `RegType` concretos, `FuncFrameAttributes` transporta máscaras/locais/flags e `FuncFrame.host(...)` consome esses dados para manter a compatibilidade com o modelo C++, liberando o construtor principal para os builders.
- `RegUtils.Reg` expõe `RegType`+ID, o builder fornece `movRI/movRR/test`, `FuncDetail` recebe `FuncSignature` + calling convention, e a infraestrutura (`FuncFrame`, `FuncValue`, `FuncArgsContext`) passa a operar com as mesmas unidades que o código C++ original.
- O pipeline x86, benchmarks e testes agora usam as APIs corretas (`FuncFrame.getArgReg`, novos construtores nomeados, `includeShadowSpace` compatível), `emit_helper.dart` aceita operandos concretos e `dart analyze` está limpo—só resta lidar com os avisos de limpeza já removidos da lista.
- Mantemos a fidelidade ao C++ enquanto documentamos os próximos refinamentos no roteiro; o fluxo de shuffle/pipeline segue alinhado com os conceitos originais.

### Referências e próximos passos

1. Continuar ajustando `emit_helper.dart` e os componentes do pipeline para que cada passo do shuffle de argumentos e da emissão gere exatamente as instruções que o código C++ faria (mesmos nomes, grupos e escolha de instruções).  
2. Capturar quaisquer regressões nas suites de testes/benchmarks ao estender o suporte para mais instruções e metadados (mantendo `X86CodeBuilder`, `FuncFrameAttr`, `FuncSignature`, etc., sincronizados).  
3. Revalidar regularmente com `dart analyze` enquanto adicionamos novos helpers ou aproximamos ainda mais o fluxo do `callconv`/RA, garantindo que a tradução siga fielmente o C++ sem alertas.
