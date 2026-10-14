# Etapa 28.69 — Recuperação de evento Unicode inválido

Adicionado teste de integração em `src/text_input.zig` para verificar `applyTracked` quando um evento de texto contém um surrogate Unicode inválido, após um prefixo que ativa Shift e estabelece seleção invertida. O teste especifica o erro `InvalidScalar`, progresso de dois eventos, preservação de seleção e conteúdo, descarte explícito do evento inválido pela engine e retomada do sufixo sem reprocessar o prefixo.

Nenhuma alteração na API pública ou no runtime; versão 0.2.0. Teste Zig não executado sem compilador Zig 0.17.0.
