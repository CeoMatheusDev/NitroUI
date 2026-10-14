# Etapa 25.1-Q1 — Qualidade contínua

Base: ZIP da etapa 25.1. Versão preservada: 0.2.0.

## Alterações

- Adicionado `.github/workflows/ci.yml` com Zig 0.17.0, formatação, testes Debug/ReleaseFast, integração headless Debug/ReleaseFast e benchmark ReleaseFast.
- README atualizado para distinguir a baseline 0.2.0 do módulo de fontes em desenvolvimento; removido aviso obsoleto de pré-publicação.
- Sem mudanças no código `src/`, `build.zig`, `build.zig.zon` ou APIs públicas.

## Validação

- Revisão estática dos arquivos e empacotamento.
- Compilação, testes e execução do CI: **não executados** neste ambiente (Zig 0.17.0 indisponível).
- Não há alegação de aprovação do GitHub Actions.

## Próximos passos

- Executar a matriz no Fedora ou CI e corrigir qualquer regressão.
- Seguir para contrato UTF-8 e geometria de texto, com testes de falha atômica.
