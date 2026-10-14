# Etapa 28.24 — Testes integrados de recuperação

Versão mantida: 0.2.0.

## Escopo

Adicionados dois testes ao `src/root.zig`, sem mudanças nas APIs públicas:

1. `stage28_24 tracked render failure reports consumed events`: geometria sem capacidade, dois eventos Unicode processados, `Progress` com prefixo consumido, texto preservado e rollback de geometria/interação.
2. `stage28_24 tracked edit failure supports next frame suffix`: falha de capacidade textual no segundo evento, confirmação de prefixo consumido, encerramento do frame, e processamento somente do evento remanescente válido no frame seguinte, sem duplicação.

## Contratos

- Edições já realizadas pertencem à aplicação e persistem após erro de renderização.
- `Progress.consumed` informa somente o prefixo de eventos processados pelo editor.
- Eventos anteriores ao prefixo não devem ser reenviados.
- O evento que falhou precisa de decisão explícita da engine (descartar, corrigir ou tentar novamente); o teste de retomada o descarta.
- Nenhuma alocação adicional e nenhuma dependência externa.

## Validação

Testes **escritos, não executados**: o compilador Zig 0.17.0 não está disponível neste ambiente. Não há comprovação de compilação, passagem dos testes ou benchmark. Verificação de integridade do arquivo ZIP é separada desses requisitos.

## Próximo passo

Executar `zig build test -Doptimize=Debug`, `zig build test -Doptimize=ReleaseFast` e `zig build integration` com Zig 0.17.0 e corrigir incompatibilidades identificadas antes de avançar funcionalidades.
