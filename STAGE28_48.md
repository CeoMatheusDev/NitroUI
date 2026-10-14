# NitroUI — Etapa 28.48

## Escopo

Teste de regressão do contrato de inicialização de `text_edit.Buffer` com
armazenamento pertencente à aplicação. Não há mudanças no runtime nem na API.

## Contrato verificado

- `Buffer.init` rejeita fonte e destino com intervalos sobrepostos, incluindo
  sobreposição parcial e aliasing exato, retornando `error.InvalidCursor`.
- Em caso de sobreposição, os bytes do armazenamento original permanecem
  inalterados.
- Uma fonte externa, não sobreposta, pode ser copiada normalmente.

## Arquivos

- `src/text_edit.zig`: teste `stage28_48 initialization rejects overlapping input without modifying caller storage`.
- `STAGE28_48.md`: este registro.

## Validação

A verificação estática do arquivo e a integridade do ZIP podem ser executadas
sem Zig. Os testes Zig, a compilação Debug/ReleaseFast, a integração e os
benchmarks permanecem **não executados**, pois Zig 0.17.0 não está disponível
no ambiente. Não presumir que o teste compila ou passa.

## Próxima prioridade

Executar `sh tools/validate_zig_017.sh` em um ambiente com Zig 0.17.0 e
corrigir eventuais falhas reais antes de ampliar o runtime.
