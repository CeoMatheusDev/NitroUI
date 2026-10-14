# Etapa 28.50 — Retentativa de substituição após falha de capacidade

## Escopo

Adicionado teste em `src/text_edit.zig` para uma seleção invertida de um byte,
cuja substituição por escalar UTF-8 de quatro bytes excede a capacidade.
O teste exige preservação integral do armazenamento, cursor e âncora em caso
de `error.OutOfCapacity`, seguida de retentativa bem-sucedida com ASCII.

## Contratos

- Memória pertence à aplicação; sem alocações.
- A falha de capacidade é atômica e não elimina a seleção.
- Uma retentativa válida substitui a seleção original sem reconstruí-la.
- Nenhuma API pública, runtime, versão ou dependência foi modificada.

## Validação

O teste Zig foi adicionado, mas **não foi executado**, porque Zig 0.17.0
não está disponível no ambiente. Verificações de empacotamento e testes Shell
são relatados separadamente e não demonstram compilação Zig.
