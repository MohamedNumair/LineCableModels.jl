
struct ScaledBessel <: InternalImpedanceFormulation end
get_description(::ScaledBessel) = "Scaled Bessel (Schelkunoff)"


@inline function (f::ScaledBessel)(
	form::Symbol, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T,
) where {T <: REALSCALAR}
	Base.@nospecialize form
	return form === :inner  ? f(Val(:inner), r_in, r_ex, rho_c, mur_c, freq)  :
		   form === :outer  ? f(Val(:outer), r_in, r_ex, rho_c, mur_c, freq)  :
		   form === :mutual ? f(Val(:mutual), r_in, r_ex, rho_c, mur_c, freq) :
		   throw(ArgumentError("Unknown ScaledBessel mode: $form"))
end

@inline function (f::ScaledBessel)(
	::Val{:inner}, r_in::T, r_ex::T, rho_c::T, mur_c::T, freq::T,
) where {T <: REALSCALAR}
	# TODO: replace with your actual formula
	println("ScaledBessel inner");
	return Complex{T}(0)
end

