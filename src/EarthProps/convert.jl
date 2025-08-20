Base.convert(::Type{EarthLayer{T}}, L::EarthLayer) where {T<:REALSCALAR} =
    EarthLayer{T}(
        _coerce_scalar_to_T(L.base_rho_g, T),
        _coerce_scalar_to_T(L.base_epsr_g, T),
        _coerce_scalar_to_T(L.base_mur_g, T),
        _coerce_scalar_to_T(L.t, T),
        _coerce_array_to_T(L.rho_g, T),
        _coerce_array_to_T(L.eps_g, T),
        _coerce_array_to_T(L.mu_g, T),
    )

Base.convert(::Type{EarthModel{T}}, M::EarthModel) where {T<:REALSCALAR} =
    EarthModel{T}(M.freq_dependence, M.vertical_layers, convert.(EarthLayer{T}, M.layers))

Base.convert(::Type{EarthModel{T}}, M::EarthModel{T}) where {T<:REALSCALAR} = M
Base.convert(::Type{EarthLayer{T}}, L::EarthLayer{T}) where {T<:REALSCALAR} = L