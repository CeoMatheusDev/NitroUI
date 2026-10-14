# Etapa 28.19 — Preservação da seleção nos limites do texto

## Diagnóstico
`moveLeftSelecting` e `moveRightSelecting` invocavam os métodos de movimento normais, que descartam `anchor`. Quando o cursor já estava no início/fim, esses métodos retornavam `false` sem mover o cursor; a âncora anterior podia ser descartada, e a seleção desaparecia indevidamente.

## Alteração
Os dois métodos de movimento com seleção retornam `false` imediatamente quando o cursor já está no limite correspondente, depois de validar o estado do buffer. Isso preserva `cursor`, `anchor` e os bytes. Fora desses limites, o comportamento anterior é mantido. Sem alteração de API pública, heap ou ownership.

## Regressões escritas
- Seleção reversa no início e seleção direta no final, com extensão posterior sobre escalar UTF-8 multibyte.
- Corrupção externa de UTF-8 e de âncora: as operações rejeitam o estado antes de modificar o conteúdo.

## Limitações
Os testes ainda exigem execução com Zig 0.17.0. O editor continua orientado a pontos de código (não grapheme clusters), sem IME. Não há garantia transacional para o lote inteiro de eventos nem para edição seguida de falha de desenho. `view()` não valida o buffer; a aplicação não deve modificar `storage` diretamente enquanto o editor está ativo.
