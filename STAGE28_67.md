# NitroUI — Etapa 28.67

## Correção: âncora colapsada em operações de exclusão

`Buffer.anchor` é público e pode conter `cursor`, um estado válido segundo
`validateState()`. Embora `selection()` retorne `null` nesse caso, as rotinas
`backspace()` e `deleteForward()` não limpavam a âncora após uma exclusão sem
seleção. No `backspace()`, isso podia transformar a âncora colapsada em uma
seleção involuntária; em ambos os métodos, violava a normalização esperada
após edição.

Correção mínima: definir `self.anchor = null` depois de uma exclusão
bem-sucedida sem seleção. As operações sem alteração e as falhas continuam
preservando o estado.

Dois testes cobrem exclusão multibyte com âncora colapsada e validam o estado
final. Sem alterações de API pública, alocações ou dependências. Versão 0.2.0.

## Validação

Os testes Zig, a integração headless e os benchmarks requerem Zig 0.17.0
real. Não são considerados aprovados sem execução. Os scripts Shell podem
ser verificados separadamente com o autoteste que utiliza Zig simulado.
