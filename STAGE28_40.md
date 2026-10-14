# Etapa 28.40 — Cobertura da infraestrutura de validação

Sem alterações no runtime nem na API pública. O teste offline `tools/test_validate_zig_017.sh` agora cobre falha de `zig version`, falha em **cada** um dos quatro comandos de build, ordem exata e sucesso integral. Verifica também ausência do compilador quando `/usr/bin` e `/bin` não o fornecem. Usa um mock de Zig; **não** comprova compilação do projeto.

Validação local: `sh -n` dos dois scripts e execução do teste offline. Testes Zig, integração e benchmarks exigem Zig 0.17.0 real e permanecem pendentes.
