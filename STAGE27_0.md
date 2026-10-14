# Etapa 27.0 — Botão com legenda UTF-8

## Escopo

- `Context.buttonText`: botão com retângulo explícito e legenda centralizada, usando o mesmo mecanismo de interação, estilo e draw commands de `button`.
- Fontes e atlas permanecem pertencentes à engine. Não há alocações dinâmicas adicionais.
- Validação de UTF-8 e métricas antes de registrar interação.
- Rollback de contadores de geometria, último comando, captura e rastreamento de IDs em erros de emissão.
- Dois testes escritos: geometria e centralização; falha de capacidade e reutilização de ID.

## Limitações

- Legenda de uma linha; não há quebra, elipse, clipping automático ao retângulo do botão nem foco por teclado.
- `font.Font.validate` deve ser aplicado aos dados externos pela integração antes de utilizá-los.
- O texto não é incorporado ao `button` original para preservar compatibilidade.

## Validação

Compilação, testes Debug/ReleaseFast e benchmarks não executados: Zig 0.17.0 indisponível neste ambiente. Não publicar sem validar.
