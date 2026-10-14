# NitroUI — Etapa 28.33: revisão de contrato e documentação

## Escopo

Corrigida documentação obsoleta em `src/root.zig` sobre recuperação de eventos do campo de texto. O comentário anterior afirmava que a API visual retornava apenas o erro e exigia chamar `text_input.applyTracked` diretamente. Isso não corresponde à API pública `Context.inputTextDraggedTracked` já existente desde a etapa 28.23.

A documentação agora instrui a engine a usar `inputTextDraggedTracked` para obter `Progress` em falhas de edição ou renderização. A política `retain_edits` e a obrigação de não repetir eventos consumidos permanecem inalteradas.

## Compatibilidade

Nenhum código executável, assinatura, dependência, estrutura ou versão foi alterado. Versão: 0.2.0.

## Auditoria estática

Foram conferidas referências `@import("*.zig")` relativas e a ausência da descrição obsoleta. Essa inspeção não substitui compilação ou execução.

## Validação pendente

Zig 0.17.0 não foi encontrado no ambiente e o acesso externo para obtê-lo não estava disponível. Portanto, `zig build test`, `zig build integration` e `zig build bench` **não foram executados**. Os testes anteriores continuam sem validação efetiva. Próxima prioridade: executar o compilador exato e corrigir os erros reais encontrados, antes de expandir o runtime.
