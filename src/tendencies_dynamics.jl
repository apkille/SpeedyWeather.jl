"""
Compute the spectral tendency of the surface pressure logarithm
"""
function surface_pressure_tendency!(Prog::PrognosticVariables{NF}, # Prognostic variables
                                    Diag::DiagnosticVariables{NF}, # Diagnostic variables
                                    l2::Int,                       # leapfrog index 2 (time step used for tendencies)
                                    M
                                    ) where {NF<:AbstractFloat}


    @unpack pres_surf                            = Prog 
    @unpack pres_surf_tend                       = Diag.tendencies
    @unpack u_grid,v_grid,div_grid               =   Diag.grid_variables
    @unpack u_mean,v_mean,div_mean,
            pres_surf_gradient_spectral_x,
            pres_surf_gradient_spectral_y,
            pres_surf_gradient_grid_x,
            pres_surf_gradient_grid_y            = Diag.intermediate_variables
    @unpack σ_levels_thick                       = M.GeoSpectral.geometry #I think this is dhs

    _,_,nlev = size(u_grid)


    
  
    #Calculate mean fields
    for k in 1:nlev
        u_mean += u_grid[:,:,k]  *σ_levels_thick[k] 
        v_mean += v_grid[:,:,k]  *σ_levels_thick[k]
        div_mean += div_grid[:,:,k]*σ_levels_thick[k]
    end

    #Now use the mean fields
    grad!(pres_surf, pres_surf_gradient_spectral_x, pres_surf_gradient_spectral_y, M.GeoSpectral)
    pres_surf_gradient_grid_x = gridded(pres_surf_gradient_spectral_x*3600)
    pres_surf_gradient_grid_y = gridded(pres_surf_gradient_spectral_x*3600) #3600 factor from Paxton/Chantry. I think this is to correct for the underflow rescaling earlier

    pres_surf_tend = spectral(-u_mean.*pres_surf_gradient_grid_x - v_mean.*pres_surf_gradient_grid_y)
    pres_surf_tend[1,1] = pres_surf_tend[1,1]*0.0 

end

"""
Compute the spectral tendency of the "vertical" velocity
"""
function vertical_velocity_tendency!(Diag::DiagnosticVariables{NF}, # Diagnostic variables
                                     M
                                     ) where {NF<:AbstractFloat}

    @unpack u_grid,v_grid,div_grid = Diag.grid_variables
    @unpack u_mean,v_mean,div_mean,pres_surf_gradient_grid_x,pres_surf_gradient_grid_y,sigma_tend,sigma_m, puv = Diag.intermediate_variables
    @unpack σ_levels_thick = M.GeoSpectral.geometry
    _,_,nlev = size(u_grid)


    for k in 1:nlev
        puv[:,:,k] = (u_grid[:,:,k] - u_mean) .* pres_surf_gradient_grid_x + (v_grid[:,:,k] - v_mean) .* pres_surf_gradient_grid_y
    end

    for k in 1:nlev
        sigma_tend[:,:,k+1] = sigma_tend[:,:,k] - σ_levels_thick[k]*(puv[:,:,k] + div_grid[:,:,k] - div_mean)
        sigma_m[:,:,k+1]    = sigma_m[:,:,k]    - σ_levels_thick[k]*puv[:,:,k]
    end

end



"""
Compute the temperature anomaly in grid point space
"""
function temperature_grid_anomaly!(Diag::DiagnosticVariables{NF}, # Diagnostic variables
                                   M
                                   ) where {NF<:AbstractFloat}

    @unpack temp_grid,temp_grid_anomaly = Diag.grid_variables
    @unpack tref = M.GeoSpectral.geometry #Note that tref is currently not defined correctly 

    _,_,nlev = size(temp_grid)


    for k in 1:nlev
        temp_grid_anomaly[:,:,k] = temp_grid[:,:,k] .- tref[k] #+ 0K correction?
    end

end





"""
Compute the spectral tendency of the zonal wind
"""
function zonal_wind_tendency!(Diag::DiagnosticVariables{NF}, # Diagnostic variables
                              M
                              )where {NF<:AbstractFloat}
    
    @unpack u_tend = Diag.tendencies
    @unpack u_grid,v_grid,vor_grid,temp_grid_anomaly= Diag.grid_variables
    @unpack sigma_tend,pres_surf_gradient_grid_x,pres_surf_gradient_grid_y,sigma_u = Diag.intermediate_variables
    
    
    @unpack rgas,σ_levels_half⁻¹_2 = M.GeoSpectral.geometry #I think this is dhsr 

    _,_,nlev = size(u_grid)


    #Update px,py

    pres_surf_gradient_grid_x = rgas*pres_surf_gradient_grid_x
    pres_surf_gradient_grid_y = rgas*pres_surf_gradient_grid_y

   

    for k in 2:nlev
        sigma_u[:,:,k] = sigma_tend[:,:,k].*(u_grid[:,:,k] - u_grid[:,:,k-1])
    end


    for k in 1:nlev
        u_tend[:,:,k] = u_tend[:,:,k] + v_grid[:,:,k].*vor_grid[:,:,k] 
                        - temp_grid_anomaly[:,:,k].*pres_surf_gradient_grid_x
                        - (sigma_u[:,:,k+1] + sigma_u[:,:,k])*σ_levels_half⁻¹_2[k]
    end


  

end



"""
Compute the spectral tendency of the meridional wind 
"""
function meridional_wind_tendency!(Diag::DiagnosticVariables{NF}, # Diagnostic variables
                                   M
                                  )where {NF<:AbstractFloat}

    @unpack v_tend = Diag.tendencies
    @unpack vor_grid,u_grid,v_grid,temp_grid_anomaly =Diag.grid_variables
    @unpack sigma_tend,sigma_u,pres_surf_gradient_grid_x,pres_surf_gradient_grid_y = Diag.intermediate_variables
    
    
    @unpack rgas,σ_levels_half⁻¹_2 = M.GeoSpectral.geometry #I think this is dhsr 


    _,_,nlev = size(u_grid)


    for k in 2:nlev
        sigma_u[:,:,k] = sigma_tend[:,:,k].*(v_grid[:,:,k] - v_grid[:,:,k-1])
    end
          
 

    for k in 1:nlev
        v_tend[:,:,k] = v_tend[:,:,k] + u_grid[:,:,k].*vor_grid[:,:,k] 
                        - temp_grid_anomaly[:,:,k].*pres_surf_gradient_grid_y
                       - (sigma_u[:,:,k+1] + sigma_u[:,:,k])*σ_levels_half⁻¹_2[k]
    end




end

"""
Compute the spectral temperature tendency
"""
function temperature_tendency!(Diag::DiagnosticVariables{NF}, # Diagnostic variables
                               M
                               )where {NF<:AbstractFloat}
    

    @unpack temp_tend = Diag.tendencies
    @unpack div_grid,temp_grid,temp_grid_anomaly = Diag.grid_variables
    @unpack sigma_u,sigma_tend,sigma_m,puv,div_mean = Diag.intermediate_variables
    @unpack tref,σ_levels_half⁻¹_2,fsgr,tref3 = M.GeoSpectral.geometry #Note that tref is currenrtly not defined correctly 
    @unpack akap = M.Parameters

    _,_,nlev = size(div_grid)



    for k in 2:nlev
        sigma_u[:,:,k] = sigma_tend[:,:,k].*(temp_grid_anomaly[:,:,k] - temp_grid_anomaly[:,:,k-1])
                    + sigma_m[:,:,k].*(tref[k] - tref[k-1])
    end

    for k in 1:nlev
        temp_tend[:,:,k] = temp_tend[:,:,k]
                        + temp_grid_anomaly[:,:,k].*div_grid[:,:,k]
                        - (sigma_u[:,:,k+1] + sigma_u[:,:,k])*σ_levels_half⁻¹_2[k]
                        + fsgr[k]*temp_grid_anomaly[:,:,k].*(sigma_tend[:,:,k+1] + sigma_tend[:,:,k])
                        + tref3[k]*(sigma_m[:,:,k+1] + sigma_m[:,:,k])
                        + akap*(temp_grid[:,:,k].*puv[:,:,k] - temp_grid_anomaly[:,:,k].*div_mean)
    end 


end




"""
Compute the humidity tendency
"""
function humidity_tendency!(Diag::DiagnosticVariables{NF}, # Diagnostic variables
                            M
                            )where {NF<:AbstractFloat}
    
    @unpack humid_tend = Diag.tendencies
    @unpack div_grid,humid_grid = Diag.grid_variables
    @unpack sigma_u,sigma_tend,= Diag.intermediate_variables

    @unpack σ_levels_half⁻¹_2 = M.GeoSpectral.geometry 

    _,_,nlev = size(div_grid)


    for k in 2:nlev
        sigma_u[:,:,k] = sigma_tend[:,:,k].*(humid_grid[:,:,k] - humid_grid[:,:,k-1])
    end
    

    # From Paxton/Chantry: dyngrtend.f90. Unsure if we need this here since we are dealing solely with humidity,
        # !spj for moisture, vertical advection is not possible between top
        # !spj two layers
        # !kuch three layers
        # !if(iinewtrace==1)then
        # do k=2,3
        #     temp(:,:,k)=0.0_dp # temp is equivalent to sigma_u. i.e a temporary array that is reused for calculations 
        # enddo
        # !endif


    for k in 1:nlev
        humid_tend[:,:,k] = humid_tend[:,:,k]
                            + humid_grid[:,:,k].*div_grid[:,:,k]
                            - (sigma_u[:,:,k+1] + sigma_u[:,:,k])*σ_levels_half⁻¹_2[k]
        end 

end

"""Spectral tendency of ∇⋅(uv*ω) from vector uv=(u,v) in grid space and absolute vorticity ω.
Step 1 (grid space): Add Coriolis f to the relative vorticity ζ (=`vor_grid`) to obtain abs vorticity ω.
Step 2 (grid space): Multiply u,v with abs vorticity ω.
Step 3 (grid space): Unscale with coslat, cosine of latitude, as the gradients will include a coslat term.
Step 4 (spectral space): convert uω/coslat, vω/coslat from grid to spectral space
Step 5 (spectral space): Compute gradients ∂/∂lon(uω/coslat) and ∂/∂lat(vω/coslat)
Step 6 (spectral space): Add ∂/∂lon(uω/coslat)+∂/∂θ(vω/coslat) and return.
"""
function divergence_uvω_spectral(   u_grid::AbstractMatrix{NF},     # zonal velocity in grid space
                                    v_grid::AbstractMatrix{NF},     # meridional velocity in grid space
                                    vor_grid::AbstractMatrix{NF},   # relative vorticity in grid space       
                                    G::GeoSpectral{NF}              # struct with geometry and spectral transform
                                    ) where {NF<:AbstractFloat}

    nlon,nlat = size(u_grid)
    @boundscheck size(u_grid) == size(v_grid) || throw(BoundsError)

    @unpack f_coriolis,coslat,coslat⁻¹,radius_earth = G.geometry
    S = G.spectral_transform

    uω_grid_coslat⁻¹ = zero(u_grid)                             # TODO preallocate elsewhere
    vω_grid_coslat⁻¹ = zero(v_grid)

    @inbounds for j in 1:nlat
        for i in 1:nlon
            ω = vor_grid[i,j] + f_coriolis[j]                   # = relative vorticity + coriolis
            uω_grid_coslat⁻¹[i,j] = -ω*u_grid[i,j]*coslat⁻¹[j]   # = u(vor+f)/cos(ϕ)
            vω_grid_coslat⁻¹[i,j] = ω*v_grid[i,j]*coslat⁻¹[j]   # = v(vor+f)/cos(ϕ)
            # uω_grid_coslat⁻¹[i,j] = ω*10*coslat⁻¹[j]   # = u(vor+f)/cos(ϕ)
            # vω_grid_coslat⁻¹[i,j] = ω*10*coslat⁻¹[j]   # = v(vor+f)/cos(ϕ)

        end
    end

    # TODO preallocate returned coefficients elsewhere
    uω_coslat⁻¹ = spectral(uω_grid_coslat⁻¹,S,one_more_l=false)         
    vω_coslat⁻¹ = spectral(vω_grid_coslat⁻¹,S,one_more_l=false)

    ∂uω_∂lon = gradient_longitude(uω_coslat⁻¹,radius_earth,one_more_l=true)                  # spectral gradients
    ∂vω_∂lat = gradient_latitude(vω_coslat⁻¹,S,-radius_earth)

    return -(∂uω_∂lon+∂vω_∂lat)                                  # add for divergence
end

function divergence_uvω_spectral!(  vor_tend::AbstractArray{Complex{NF},3}, # vorticity tendency  
                                    u_grid::AbstractArray{NF,3},            # zonal velocity in grid space
                                    v_grid::AbstractArray{NF,3},            # meridional velocity in grid space
                                    vor_grid::AbstractArray{NF,3},          # relative vorticity in grid space       
                                    G::GeoSpectral{NF}                      # struct with geometry and spectral transform
                                    ) where {NF<:AbstractFloat}
    
    for k in 1:size(vor_tend)[end]
        u_grid_layer = view(u_grid,:,:,k)
        v_grid_layer = view(v_grid,:,:,k)
        vor_grid_layer = view(vor_grid,:,:,k)
        tend = divergence_uvω_spectral(u_grid_layer,v_grid_layer,vor_grid_layer,G)
        
        lmax,mmax = size(vor_tend)[1:2]

        for m in 1:mmax
            for l in m:lmax
                vor_tend[l,m,k] = tend[l,m]
            end
        end
    end
end

function gridded!(  diagn::DiagnosticVariables{NF}, # all diagnostic variables
                    progn::PrognosticVariables{NF}, # all prognostic variables
                    M::ModelSetup,                  # everything that's constant
                    lf::Int=2                       # leapfrog index
                    ) where NF
    
    @unpack vor = progn                             # relative vorticity
    @unpack vor_grid, u_grid, v_grid = diagn.grid_variables
    @unpack stream_function, coslat_u, coslat_v = diagn.intermediate_variables
    
    G = M.geospectral.geometry
    S = M.geospectral.spectral_transform
    @unpack lmax,ϵlms = S
    @unpack radius_earth = M.constants

    # fill!(view(vor,lmax+1,:,:,:),0)

    vor_lf = view(vor,:,:,lf,:)     # pick leapfrog index with mem allocation
    gridded!(vor_grid,vor_lf,S)     # get vorticity on grid from spectral vor_lf
    ∇⁻²!(stream_function,vor_lf,S)  # invert Laplacian ∇² for stream function
    
    # coslat*v = zonal gradient of stream function
    # coslat*u = meridional gradient of stream function
    gradient_longitude!(coslat_v, stream_function,     radius_earth)
    gradient_latitude!( coslat_u, stream_function, S, -radius_earth)
    
    gridded!(u_grid,coslat_u,S)              # get u,v on grid from spectral
    gridded!(v_grid,coslat_v,S)
    unscale_coslat!(u_grid,G)                # undo the coslat scaling from gradients
    unscale_coslat!(v_grid,G)

    return nothing
end