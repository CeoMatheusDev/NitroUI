# Etapa 28.22 — Contrato explícito para falha de renderização de texto

## Decisão

O widget de edição **preserva alterações já aplicadas ao armazenamento do chamador** quando a renderização falha. A recuperação por checkpoint restaura somente geometria e interação da NitroUI. Não há rollback textual implícito. Esta política é exposta em `Context.text_render_failure_policy` (`.retain_edits`) e documentada junto à API.

Motivação: reverter texto exigiria cópia ou journal dos bytes mutados, estado extra e um contrato de ownership/capacidade que não existe atualmente. Evita-se alterar assinaturas públicas e introduzir alocações no hot path.

## Regressão

Teste `stage28_22 text render capacity failure retains edit and rolls back widget`: fornece buffers geométricos vazios, solicita foco, insere `B` em `A`, verifica `error.OutOfCapacity`, texto `AB`, deslocamento inalterado e contadores de geometria/IDs restaurados.

## Contrato da engine

Não reenviar eventos de texto que já produziram edições quando a emissão de draw commands falhar. `text_input.applyTracked` fornece progresso para processamento manual; o widget visual ainda não expõe progresso granular quando um lote de edição falha.

## Validação

Inspeção estática e integridade do ZIP; compilação e execução de testes **não realizadas** (Zig 0.17.0 indisponível). Sem benchmarks. Versão preservada em 0.2.0. Nenhuma publicação remota.
