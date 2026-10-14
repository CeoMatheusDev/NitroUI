# Etapa 28.12 — Campo de texto visual inicial

## Escopo
Adicionada `Context.inputText`, com fundo, texto UTF-8, destaque de seleção e cursor; usa `text_input.apply`, `text_edit.Buffer`, fonte e draw commands existentes. Eventos ordenados e storage são da engine. O widget não aloca memória.

## Limites conhecidos
- Não há rolagem horizontal nem clique para posicionar cursor.
- A renderização respeita o clip fornecido pelo chamador, que deve limitar o campo; não cria clip próprio.
- `text_input.apply` aplica um lote parcialmente se um evento posterior falhar. Alterações do editor também podem persistir caso a geometria falhe; rollback existente restaura somente estado visual/interação.
- Sem IME, grapheme clusters, clipboard ou undo/redo.
- A fonte precisa oferecer os glifos usados; falhas de glifo podem ocorrer após edição.

## Validação
ZIP verificado com biblioteca zipfile. Zig 0.17.0 não disponível; compilação, testes e benchmarks não executados. Versão 0.2.0 inalterada. Nenhum push remoto.
