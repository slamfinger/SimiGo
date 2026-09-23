# R-INTERNAL-5 — L(g;P,θ) 定义域 / 函数类型声明

日期：2026-09-23

研究者明确声明：

```
R-INTERNAL-5 = L5-3

L : Dom(L) → ℝ
```

L5-3 将规则级 aggregate evaluation 声明为一个以 `Dom(L)` 为定义域、以有限实数为值域的标量函数。定义域 `Dom(L)` 暂不具体展开；其合法性由当前已声明的 expectation / measurability / definedness 边界约束，避免在本门静默补入尚未声明的参数域、可积性条件或具体概率空间。

现有公式继续保持：

```
L(g;P,θ) = E_θ[C_LOSS(g(W),W)]
R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)
```

本声明不把 `Dom(L)` 自动等同于 `𝒢_adm(P)`、`𝒢_adm(P) × Θ` 或其他具体笛卡尔积；也不实例化 expectation 的存在性、有限性、可测性或可积性条件。

本声明不改变：
- `P : PROJECTION_CANDIDATE`
- `δ : DECISION_GENERATION_PARAMETER`
- `θ : REGIME_PARAMETER`
- `𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY`
- `𝒢_adm(P) ⊆ {g | g : W → A}`
- `C_LOSS : A × W → ℝ`
- `R-ASSEMBLY-6 = I2`
- `R-ASSEMBLY-7 = J1`
- `R-ASSEMBLY-8 = K3`
- `R-ASSEMBLY-9 = L3`
- `R-ASSEMBLY-10 = M4`

L5-3 仅关闭 L 的定义域/函数类型层级，不声明 R_OBJECT，不定义 R_oracle，不解除 Δ、FinLoss、NECT 或 STEP⑤ downstream block。

No implementation, harness, data collection, profiling, measurement, experiment, or STEP⑤/STEP⑥ authorization is created by this declaration.
