# Etapa 28.7 — Recuperação de navegação com elegibilidade dinâmica

- Quando Tab seleciona um ID da ordem anterior que desapareceu ou foi desabilitado, `endFrame()` agora seleciona um ID elegível da ordem **atual**: o primeiro para Tab e o último para Shift+Tab.
- O foco de recuperação fica disponível **após** `endFrame()`, para utilização no próximo frame. Não há ativação retroativa no frame corrente.
- A política é uma recuperação determinística para a primeira/última posição, **não** uma busca circular exata pelo próximo ID elegível após o alvo anterior. Essa limitação permanece para a evolução posterior.
- Dois testes de regressão cobrem Tab e Shift+Tab com alteração dinâmica de elegibilidade.
- Nenhuma alocação, dependência ou mudança de assinatura pública.
- Zig 0.17.0 não está instalado no ambiente: testes e compilação **não executados**.
