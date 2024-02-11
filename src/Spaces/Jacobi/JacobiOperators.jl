## Derivative

function Derivative(J::MaybeNormalized{<:Jacobi}, k::Number)
    assert_integer(k)
    return ConcreteDerivative(J,k)
end

rangespace(D::ConcreteDerivative{<:MaybeNormalized{<:Jacobi}}) = Jacobi(D.space.b+D.order,D.space.a+D.order,domain(D))
bandwidths(D::ConcreteDerivative{<:MaybeNormalized{<:Jacobi}}) = -D.order,D.order
isdiag(D::ConcreteDerivative{<:MaybeNormalized{<:Jacobi}}) = false

function getindex(D::ConcreteDerivative{<:Jacobi}, k::Integer, j::Integer)
    m = D.order
    sp = domainspace(D)
    a, b = sp.a, sp.b
    x = j + a + b
    j == k+m ? eltype(D)(pochhammer(x, m)/complexlength(domain(D))^m) : zero(eltype(D))
end


# Evaluation

Evaluation(S::MaybeNormalized{<:Jacobi},x::Number,o::Integer) = ConcreteEvaluation(S,x,o)

ldiffbc(d::MaybeNormalized{<:Union{Chebyshev, Ultraspherical, Jacobi}},k) = Evaluation(d,LeftEndPoint,k)
rdiffbc(d::MaybeNormalized{<:Union{Chebyshev, Ultraspherical, Jacobi}},k) = Evaluation(d,RightEndPoint,k)

## Integral

@static if VERSION >= v"1.8"
    Base.@constprop :aggressive Integral(J::Jacobi, k::Number) = _Integral(J, k)
else
    Integral(J::Jacobi, k::Number) = _Integral(J, k)
end

@inline function _Integral(J::Jacobi,k::Number)
    assert_integer(k)
    @assert k > 0 "order of integral must be > 0"
    if k > 1
        Q=Integral(J,1)
        IntegralWrapper(TimesOperator(Integral(rangespace(Q),k-1),Q),k,J)
    elseif J.a > 0 && J.b > 0   # we have a simple definition
        ConcreteIntegral(J,1)
    else   # convert and then integrate
        abmin = min(J.a, J.b)
        nsteps = length(abmin:0)
        a = J.a + nsteps
        b = J.b + nsteps
        sp=Jacobi(b,a,domain(J))
        C=_conversion_shiftordersbyone(J,sp)
        Qconc=ConcreteIntegral(sp,1)
        IntegralWrapper(TimesOperator(Qconc,C),1,J,rangespace(Qconc))
    end
end


rangespace(D::ConcreteIntegral{<:Jacobi}) = Jacobi(D.space.b-D.order,D.space.a-D.order,domain(D))
bandwidths(D::ConcreteIntegral{<:Jacobi}) = D.order,-D.order
isdiag(D::ConcreteIntegral{<:Jacobi}) = false

function getindex(T::ConcreteIntegral{<:Jacobi}, k::Integer, j::Integer)
    @assert T.order==1
    if k≥2 && j==k-1
        complexlength(domain(T))./(k+T.space.a+T.space.b-2)
    else
        zero(eltype(T))
    end
end


## Volterra Integral operator

Volterra(d::IntervalOrSegment) = Volterra(Legendre(d))
function Volterra(S::Jacobi, order::Integer)
    @assert S.a == S.b == 0.0
    @assert order==1
    ConcreteVolterra(S,order)
end

rangespace(V::ConcreteVolterra{J}) where {J<:Jacobi}=Jacobi(-1.0,0.0,domain(V))
bandwidths(::ConcreteVolterra{<:Jacobi}) = 1,0

function getindex(V::ConcreteVolterra{J},k::Integer,j::Integer) where J<:Jacobi
    d=domain(V)
    C = complexlength(d)/2
    if k≥2
        if j==k-1
            C/(k-1.5)
        elseif j==k
            -C/(k-0.5)
        else
            zero(eltype(V))
        end
    else
        zero(eltype(V))
    end
end


for (Func,Len,Sum) in ((:DefiniteIntegral,:complexlength,:sum),(:DefiniteLineIntegral,:arclength,:linesum))
    ConcFunc = Symbol(:Concrete, Func)

    @eval begin
        $Func(S::Jacobi{<:IntervalOrSegment}) = $ConcFunc(S)

        function getindex(Σ::$ConcFunc{<:Jacobi{<:IntervalOrSegment},T}, k::Integer) where {T}
            dsp = domainspace(Σ)

            if dsp.b == dsp.a == 0
                # TODO: copy and paste
                k == 1 ? strictconvert(T,$Sum(Fun(dsp,[one(T)]))) : zero(T)
            else
                strictconvert(T,$Sum(Fun(dsp,[zeros(T,k-1);1])))
            end
        end

        function bandwidths(Σ::$ConcFunc{<:Jacobi{<:IntervalOrSegment}})
            if domainspace(Σ).b == domainspace(Σ).a == 0
                0,0  # first entry
            else
                0,ℵ₀
            end
        end
    end
end

function _conversion_shiftordersbyone(L::Jacobi, M::Jacobi)
    dl=domain(L)
    dm=domain(M)
    # We split this into steps where a and b are changed by 1:
    # Define the intermediate space J = Jacobi(M.b, L.a, dm)
    # Conversion(L, M) == Conversion(J, M) * Conversion(L, J)
    # Conversion(L, J) = Conversion(Jacobi(L.b, L.a, dm), Jacobi(M.b, L.a, dm))
    # Conversion(J, M) = Conversion(Jacobi(M.b, L.a, dm), Jacobi(M.b, M.a, dm))
    CLJ = [ConcreteConversion(Jacobi(b-1,L.a,dm), Jacobi(b, L.a, dm)) for b in M.b:-1:L.b+1]
    CJM = [ConcreteConversion(Jacobi(M.b,a-1,dm), Jacobi(M.b, a, dm)) for a in M.a:-1:L.a+1]
    bw = bandwidthssum(bandwidths, CLJ) .+ bandwidthssum(bandwidths, CJM)
    bbw = bandwidthssum(blockbandwidths, CLJ) .+ bandwidthssum(blockbandwidths, CJM)
    sbbw = bandwidthssum(subblockbandwidths, CLJ) .+ bandwidthssum(subblockbandwidths, CJM)
    op1 = isempty(CJM) ? CLJ[1] : CJM[1]
    opend = isempty(CLJ) ? CJM[end] : CLJ[end]
    ts = (size(op1, 1), size(opend, 2))
    # we deliberately use Operator{T} to improve type-stability in Conversion
    C = Operator{eltype(eltype(CLJ))}[CJM; CLJ]
    return ConversionWrapper(TimesOperator(C, bw, ts, bbw, sbbw), L, M)
end

## Conversion
# We can only increment by a or b by one, so the following
# multiplies conversion operators to handle otherwise

function Conversion(L::Jacobi,M::Jacobi)
    domain(L) == reverseorientation(domain(M)) &&
        return ConversionWrapper(Conversion(reverseorientation(L), M)*ReverseOrientation(L))

    domain(L) == domain(M) || domain(L) == reverseorientation(domain(M)) ||
        throw(ArgumentError("Domains must be the same"))

    dm=domain(M)
    dl=domain(L)

    La, Lb = L.a, L.b
    Ma, Mb = M.a, M.b

    if isapproxinteger(La-Ma) && isapproxinteger(Lb-Mb) && Mb >= Lb && Ma >= La
        if isapprox(La,Ma) && isapprox(Lb,Mb)
            return ConversionWrapper(Operator(I,L), L, M)
        elseif (isapprox(Lb+1,Mb) && isapprox(La,Ma)) ||
                (isapprox(Lb,Mb) && isapprox(La+1,Ma))
            return ConcreteConversion(L,M)
        elseif La ≈ Lb && isapproxminhalf(La) && Ma ≈ Mb
            C = Chebyshev(dl)
            Conv_LC = ConcreteConversion(L, C)
            U = Ultraspherical(M)
            Conv_UM = ConcreteConversion(U, M)
            return ConversionWrapper(Conv_UM * Conversion(C, U) * Conv_LC, L, M)
            # return Conversion(L,Chebyshev(dl),Ultraspherical(M),M)
        # elseif La ≈ Lb && Ma ≈ Mb && isapproxminhalf(Ma)
        #     C = Chebyshev(dm)
        #     Conv_CM = ConcreteConversion(C, M)
        #     U = Ultraspherical(L)
        #     Conv_LU = ConcreteConversion(L, U)
        #     return ConversionWrapper(Conv_CM * Conversion(U, C) * Conv_LU, L, M)
        #     # return Conversion(L,Ultraspherical(L),Chebyshev(dm),M)
        elseif La ≈ Lb && Ma ≈ Mb && !isapproxminhalf(Ma)
            UL = Ultraspherical(L)
            Conv_LU = ConcreteConversion(L, UL)
            UM = Ultraspherical(M)
            Conv_UM = ConcreteConversion(UM, M)
            return ConversionWrapper(Conv_UM * ultraconv_nonequal(UL, UM) * Conv_LU, L, M)
            # return Conversion(L,Ultraspherical(L),Ultraspherical(M),M)
        else
            return _conversion_shiftordersbyone(L, M)
        end
    elseif isapproxhalfoddinteger(La - Ma) && isapproxhalfoddinteger(Lb - Mb)
        if La ≈ Lb && Ma ≈ Mb && isapproxminhalf(Ma)
            C = Chebyshev(dm)
            Conv_CM = ConcreteConversion(C, M)
            U = Ultraspherical(L)
            Conv_LU = ConcreteConversion(L, U)
            return ConversionWrapper(Conv_CM * Conversion(U, C) * Conv_LU, L, M)
            # return Conversion(L,Ultraspherical(L),Chebyshev(dm),M)
        elseif La ≈ Lb && isapproxminhalf(La) && Ma ≈ Mb && Ma >= La
            C = Chebyshev(dl)
            Conv_LC = ConcreteConversion(L, C)
            U = Ultraspherical(M)
            Conv_UM = ConcreteConversion(U, M)
            return ConversionWrapper(Conv_UM * Conversion(C, U) * Conv_LC, L, M)
            # return Conversion(L,Chebyshev(dl),Ultraspherical(M),M)
        elseif La ≈ Lb && Ma ≈ Mb && Ma >= La
            UL = Ultraspherical(L)
            Conv_LU = ConcreteConversion(L, UL)
            UM = Ultraspherical(M)
            Conv_UM = ConcreteConversion(UM, M)
            return ConversionWrapper(Conv_UM * Conversion(UL, UM) * Conv_LU, L, M)
        end
    end

    throw(ArgumentError("please implement $L → $M"))
end

bandwidths(::ConcreteConversion{<:Jacobi,<:Jacobi}) = (0,1)

# These methods help with constant propagating the bandwidths of a KroneckerOperator
isdiag(::ConversionWrapper{<:Chebyshev,<:Jacobi}) = false
isdiag(::ConversionWrapper{<:Jacobi,<:Jacobi,<:Any,<:ConstantOperator}) = true
isdiag(::ConversionWrapper{<:Union{Ultraspherical,Jacobi},<:Union{Ultraspherical,Jacobi}}) = false

# These operators are banded and UpperTriangular
israggedbelow(::ConversionWrapper{<:Chebyshev,<:Jacobi}) = true
israggedbelow(::ConversionWrapper{<:Union{Ultraspherical,Jacobi},<:Union{Ultraspherical,Jacobi}}) = true

function getindex(C::ConcreteConversion{<:Jacobi,<:Jacobi,T},k::Integer,j::Integer) where {T}
    L=C.domainspace
    if L.b+1==C.rangespace.b
        if j==k
            k==1 ? strictconvert(T,1) : strictconvert(T,(L.a+L.b+k)/(L.a+L.b+2k-1))
        elseif j==k+1
            strictconvert(T,(L.a+k)./(L.a+L.b+2k+1))
        else
            zero(T)
        end
    elseif L.a+1==C.rangespace.a
        if j==k
            k==1 ? strictconvert(T,1) : strictconvert(T,(L.a+L.b+k)/(L.a+L.b+2k-1))
        elseif j==k+1
            strictconvert(T,-(L.b+k)./(L.a+L.b+2k+1))
        else
            zero(T)
        end
    else
        error("Not implemented")
    end
end




# return the space that has banded Conversion to the other
function conversion_rule(A::Jacobi,B::Jacobi)
    if isapproxinteger(A.a-B.a) && isapproxinteger(A.b-B.b)
        Jacobi(min(A.b,B.b),min(A.a,B.a),domain(A))
    else
        NoSpace()
    end
end



## Ultraspherical Conversion

# Assume m is compatible

function Conversion(A::PolynomialSpace, B::Jacobi)
    @assert domain(A) == domain(B)
    J = Jacobi(A)
    J == B ? ConcreteConversion(A,B) :
             ConversionWrapper(SpaceOperator(TimesOperator(Conversion(J,B),Conversion(A,J)), A, B))
end

function Conversion(A::Jacobi, B::PolynomialSpace)
    @assert domain(A) == domain(B)
    J = Jacobi(B)
    J == A ? ConcreteConversion(A,B) :
             ConversionWrapper(SpaceOperator(TimesOperator(Conversion(J,B),Conversion(A,J)), A, B))
end

function Conversion(A::Jacobi, B::Chebyshev)
    @assert domain(A) == domain(B)
    if isequalminhalf(A.a) && isequalminhalf(A.b)
        ConcreteConversion(A,B)
    elseif A.a == A.b == 0
        ConversionWrapper(SpaceOperator(ConcreteConversion(Ultraspherical(A), B), A, B))
    elseif A.a == A.b
        US = Ultraspherical(A)
        ConversionWrapper(TimesOperator(Conversion(US,B), ConcreteConversion(A,US)), A, B)
    else
        J = Jacobi(B)
        ConcreteConversion(J,B)*Conversion(A,J)
    end
end

function Conversion(A::Chebyshev, B::Jacobi)
    @assert domain(A) == domain(B)
    if isequalminhalf(B.a) && isequalminhalf(B.b)
        ConcreteConversion(A,B)
    elseif B.a == B.b == 0
        ConversionWrapper(SpaceOperator(ConcreteConversion(A, Ultraspherical(B)), A, B))
    elseif B.a == B.b
        US = Ultraspherical(B)
        ConversionWrapper(TimesOperator(ConcreteConversion(US,B), Conversion(A,US)), A, B)
    else
        J = Jacobi(A)
        Conversion(J,B)*ConcreteConversion(A,J)
    end
end


@inline function _Conversion(A::Jacobi, B::Ultraspherical)
    @assert domain(A) == domain(B)
    if isequalminhalf(A.a) && isequalminhalf(A.b)
        C = Chebyshev(domain(A))
        ConversionWrapper(
            TimesOperator(Conversion(C,B), ConcreteConversion(A,C)), A, B)
    elseif isequalminhalf(A.a - order(B)) && isequalminhalf(A.b - order(B))
        ConcreteConversion(A,B)
    elseif A.a == A.b == 0
        ConversionWrapper(SpaceOperator(Conversion(Ultraspherical(A), B), A, B))
    elseif A.a == A.b
        US = Ultraspherical(A)
        ConversionWrapper(
            TimesOperator(Conversion(US,B), ConcreteConversion(A,US)), A, B)
    else
        J = Jacobi(B)
        ConcreteConversion(J,B)*Conversion(A,J)
    end
end

@inline function _Conversion(A::Ultraspherical, B::Jacobi)
    @assert domain(A) == domain(B)
    if isequalminhalf(B.a) && isequalminhalf(B.b)
        C = Chebyshev(domain(B))
        ConversionWrapper(
            TimesOperator(ConcreteConversion(C, B), Conversion(A, C)), A, B)
    elseif isequalminhalf(B.a - order(A)) && isequalminhalf(B.b - order(A))
        ConcreteConversion(A,B)
    elseif B.a == B.b == 0
        ConversionWrapper(SpaceOperator(Conversion(A, Ultraspherical(B)), A, B))
    elseif B.a == B.b
        US = Ultraspherical(B)
        ConversionWrapper(
            TimesOperator(ConcreteConversion(US,B), Conversion(A,US)), A, B)
    else
        J = Jacobi(A)
        Conversion(J,B)*ConcreteConversion(A,J)
    end
end

@static if VERSION >= v"1.8"
    Base.@constprop :aggressive Conversion(A::Jacobi, B::Ultraspherical) = _Conversion(A, B)
    Base.@constprop :aggressive Conversion(A::Ultraspherical, B::Jacobi) = _Conversion(A, B)
else
    Conversion(A::Jacobi, B::Ultraspherical) = _Conversion(A, B)
    Conversion(A::Ultraspherical, B::Jacobi) = _Conversion(A, B)
end



bandwidths(::ConcreteConversion{<:Chebyshev,<:Jacobi}) = 0,0
bandwidths(::ConcreteConversion{<:Jacobi,<:Chebyshev}) = 0,0


bandwidths(::ConcreteConversion{<:Ultraspherical,<:Jacobi}) = 0,0
bandwidths(::ConcreteConversion{<:Jacobi,<:Ultraspherical}) = 0,0

#TODO: Figure out how to unify these definitions
function getindex(::ConcreteConversion{<:Chebyshev,<:Jacobi,T}, k::Integer, j::Integer) where {T}
    if j==k
        one(T)/jacobip(T,k-1,-one(T)/2,-one(T)/2,one(T))
    else
        zero(T)
    end
end

function BandedMatrix(S::SubOperator{T,ConcreteConversion{CC,J,T},NTuple{2,UnitRange{Int}}}) where {J<:Jacobi,CC<:Chebyshev,T}
    ret=BandedMatrix(Zeros, S)
    kr,jr = parentindices(S)
    k=(kr ∩ jr)

    vals = one(T)./jacobip(T,k .- 1,-one(T)/2,-one(T)/2,one(T))

    ret[band(bandshift(S))] = vals
    ret
end


function getindex(::ConcreteConversion{<:Jacobi,<:Chebyshev,T}, k::Integer, j::Integer) where {T}
    if j==k
        jacobip(T,k-1,-one(T)/2,-one(T)/2,one(T))
    else
        zero(T)
    end
end

function BandedMatrix(S::SubOperator{T,ConcreteConversion{J,CC,T},NTuple{2,UnitRange{Int}}}) where {J<:Jacobi,CC<:Chebyshev,T}
    ret=BandedMatrix(Zeros, S)
    kr,jr = parentindices(S)
    k=(kr ∩ jr)

    vals = jacobip(T,k.-1,-one(T)/2,-one(T)/2,one(T))

    ret[band(bandshift(S))] = vals
    ret
end


function getindex(C::ConcreteConversion{<:Ultraspherical,<:Jacobi,T}, k::Integer, j::Integer) where {T}
    if j==k
        S=rangespace(C)
        U=domainspace(C)
        if S.a == S.b == 0 && isequalhalf(order(U))
            oneunit(T)
        else
            jp=jacobip(T,k-1,S.a,S.b,one(T))
            um=strictconvert(Operator{T}, Evaluation(setcanonicaldomain(U),RightEndPoint,0))[k]::T
            (um/jp)::T
        end
    else
        zero(T)
    end
end

function BandedMatrix(S::SubOperator{T,ConcreteConversion{US,J,T},NTuple{2,UnitRange{Int}}}) where {US<:Ultraspherical,J<:Jacobi,T}
    ret=BandedMatrix(Zeros, S)
    kr,jr = parentindices(S)
    k=(kr ∩ jr)

    C = parent(S)
    sp = rangespace(C)
    U = domainspace(C)
    if sp.a == 0 && sp.b == 0 && isequalhalf(order(U))
        ret[band(bandshift(S))] .= oneunit(T)
    else
        jp=jacobip(T,k.-1,sp.a,sp.b,one(T))
        um=Evaluation(T,setcanonicaldomain(U),RightEndPoint,0)[k]
        vals = um./jp

        ret[band(bandshift(S))] = vals
    end
    ret
end



function getindex(C::ConcreteConversion{<:Jacobi,<:Ultraspherical,T}, k::Integer, j::Integer) where {T}
    if j==k
        S=domainspace(C)
        U = rangespace(C)
        if S.a == S.b == 0 && isequalhalf(order(U))
            oneunit(T)
        else
            jp=jacobip(T,k-1,S.a,S.b,one(T))
            um=Evaluation(T,setcanonicaldomain(rangespace(C)),RightEndPoint,0)[k]
            jp/um::T
        end
    else
        zero(T)
    end
end

function BandedMatrix(S::SubOperator{T,ConcreteConversion{J,US,T},NTuple{2,UnitRange{Int}}}) where {US<:Ultraspherical,J<:Jacobi,T}
    ret=BandedMatrix(Zeros, S)
    kr,jr = parentindices(S)
    k=(kr ∩ jr)

    C = parent(S)
    sp=domainspace(C)
    U = rangespace(C)
    if sp.a == 0 && sp.b == 0 && isequalhalf(order(U))
        ret[band(bandshift(S))] .= oneunit(T)
    else
        jp=jacobip(T,k.-1,sp.a,sp.b,one(T))
        um=Evaluation(T,setcanonicaldomain(U),RightEndPoint,0)[k]
        vals = jp./um
        ret[band(bandshift(S))] = vals
    end
    ret
end

function union_rule(A::Jacobi,B::Jacobi)
    if domainscompatible(A,B)
        Jacobi(min(A.b,B.b),min(A.a,B.a),domain(A))
    else
        NoSpace()
    end
end

function maxspace_rule(A::Jacobi,B::Jacobi)
    if isapproxinteger(A.a-B.a) && isapproxinteger(A.b-B.b)
        Jacobi(max(A.b,B.b),max(A.a,B.a),domain(A))
    else
        NoSpace()
    end
end


function union_rule(A::Chebyshev,B::Jacobi)
    if domainscompatible(A, B)
        if isapproxminhalf(B.a) && isapproxminhalf(B.b)
            # the spaces are the same
            A
        else
            union(Jacobi(A),B)
        end
    else
        if isapproxminhalf(B.a) && isapproxminhalf(B.b)
            union(A, Chebyshev(domain(B)))
        else
            NoSpace()
        end
    end
end
function union_rule(A::Ultraspherical,B::Jacobi)
    m=order(A)
    if domainscompatible(A, B)
        if isapproxminhalf(B.a-m) && isapproxminhalf(B.b-m)
            # the spaces are the same
            A
        else
            union(Jacobi(A),B)
        end
    else
        if isapproxminhalf(B.a-m) && isapproxminhalf(B.b-m)
            union(A, Ultraspherical(m, domain(B)))
        else
            NoSpace()
        end
    end
end

for (OPrule,OP) in ((:conversion_rule,:conversion_type), (:maxspace_rule,:maxspace))
    @eval begin
        function $OPrule(A::Chebyshev, B::Jacobi)
            if isapproxminhalf(B.a) && isapproxminhalf(B.b)
                # the spaces are the same
                B # return the Jacobi for type-stability
            else
                $OP(Jacobi(A),B)
            end
        end
        function $OPrule(A::Ultraspherical, B::Jacobi)
            m = order(A)
            if isapproxminhalf(B.a - m) && isapproxminhalf(B.b - m)
                # the spaces are the same
                B # return the Jacobi for type-stability
            else
                $OP(Jacobi(A), B)
            end
        end
    end
end

hasconversion(a::Jacobi,b::Chebyshev) = hasconversion(a,Jacobi(b))
hasconversion(a::Chebyshev,b::Jacobi) = hasconversion(Jacobi(a),b)

hasconversion(a::Jacobi,b::Ultraspherical) = hasconversion(a,Jacobi(b))
hasconversion(a::Ultraspherical,b::Jacobi) = hasconversion(Jacobi(a),b)




## Special Multiplication
# special multiplication operators exist when multiplying by
# (1+x) or (1-x) by _decreasing_ the parameter.  Thus the







# represents [b+(1+z)*d/dz] (false) or [a-(1-z)*d/dz] (true)
struct JacobiSD{T} <:Operator{T}
    lr::Bool
    S::Jacobi
end

JacobiSD(lr,S)=JacobiSD{Float64}(lr,S)

convert(::Type{Operator{T}},SD::JacobiSD) where {T}=JacobiSD{T}(SD.lr,SD.S)

domain(op::JacobiSD)=domain(op.S)
domainspace(op::JacobiSD)=op.S
rangespace(op::JacobiSD)=op.lr ? Jacobi(op.S.b+1,op.S.a-1,domain(op.S)) : Jacobi(op.S.b-1,op.S.a+1,domain(op.S))
bandwidths(::JacobiSD)=0,0

function getindex(op::JacobiSD,A,k::Integer,j::Integer)
    m=op.lr ? op.S.a : op.S.b
    if k==j
        k+m-1
    else
        zero(eltype(op))
    end
end
