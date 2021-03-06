;set up the start and end time for obtaining the in-situ observations
pro compare_insitu, dir_sim=dir_sim, dir_plot=dir_plot,     $
                    extra_plt_info=extra_plt_info,          $
                    UseTimePlotName=UseTimePlotName,        $
                    CharSizeLocal=CharSizeLocal,            $
                    DoPlotTe=DoPlotTe, Model=Model,         $
                    dir_obs=dir_obs

  if (not keyword_set(dir_sim)) then begin
     if (file_test('./simdata', /directory)) then begin
        dir_sim  = './simdata/'
        print, ' Uses the default dir_sim = ./simdata'
     endif else begin
        print, ' Please specify the directory containing simulation results'
        return
     endelse
  endif

  if (not keyword_set(dir_plot)) then begin
     if (file_test('./output', /directory) eq 0) then file_mkdir, './output'
     dir_plot = './output'
     print, ' Saves into the default dir_plot = ./output'
  endif

  if (not keyword_set(dir_obs)) then begin
     if (file_test('./obsdata', /directory) eq 0) then file_mkdir, './output'
     dir_obs = './obsdata'
     print, ' Saves into the default dir_obs = ./obsdata'
  endif

  if (not keyword_set(extra_plt_info)) then begin
     extra_plt_info = ''
  endif else begin
     if (strmid(extra_plt_info,0,1) ne '_') then $
        extra_plt_info = '_' + extra_plt_info
  endelse
  if (not keyword_set(UseTimePlotName)) then UseTimePlotName = 0
  if (not keyword_set(CharSizeLocal))   then CharSizeLocal = 2.5
  if (not keyword_set(DoPlotTe))        then DoPlotTe = 0

  if (not keyword_set(Model)) then Model = 'AWSoM'

  files_sim = file_search(dir_sim+'/*sat', count = nSimFile)

  dirs_adapt = file_search(dir_sim+'/run[01][0-9]', count = nDir)

  if (nSimFile eq 0 and nDir eq 0) then begin
     print, ' no simulation data'
     return
  endif

  print, "+++++++++++++++++++++++++++++++++++++++++++++++++++++"
  print, "compare_remote: dir_obs    =", dir_obs
  print, "compare_remote: files_sim  =", files_sim
  print, "compare_remote: dirs_adapt =", dirs_adapt

  if nDir gt 0 then begin
     TypeADAPT_I = ['earth', 'sta', 'stb']

     for iType = 0, n_elements(TypeADAPT_I)-1 do begin
        TypeADAPT = TypeADAPT_I[iType]
        files_adapt_one = file_search(dirs_adapt+'/IH/*'+TypeADAPT+'*sat', $
                                      count = nFileAdaptOne)

        set_plot,'PS'
        device,/encapsulated
        device,filename=dir_sim+'/'+TypeADAPT+'_all.eps',/color,bits_per_pixel=8
        device,xsize=20,ysize=20
        !p.multi=[0,1,4]

        IsOverPlot = 0
        DoLegend   = 1

        for iFile=0, nFileAdaptOne-1 do begin
           file_sim_adapt=files_adapt_one[iFile]

           read_swmf_sat, file_sim_adapt, time_swmf, n_swmf, ux_swmf, uy_swmf,        $
                          uz_swmf, bx_swmf, by_swmf, bz_swmf, ti_swmf, te_swmf,       $
                          ut_swmf, ur_swmf, B_swmf, DoContainData=DoContainData,      $
                          TypeData=TypeData, TypePlot=TypePlot,                       $
                          start_time=start_time, end_time=end_time

           if DoContainData ne 1 then begin
              print, " Error: filename=", file_sim_adapt, " does not contain any data"
              continue
           endif

           get_insitu_data, start_time, end_time, TypeData, u_obs, n_obs, tem_obs,  $
                            mag_obs, time_obs, DoContainData=DoContainData

           if DoContainData ne 1 then begin
              print, " Error: no observational data are found."
              continue
           endif

           plot_insitu, time_obs, u_obs,  n_obs,  tem_obs, mag_obs,                 $
                        time_swmf, ur_swmf, n_swmf,  ti_swmf,  te_swmf, B_swmf,     $
                        start_time, end_time, typeData=typeData,                    $
                        charsize=CharSizeLocal, DoPlotTe = DoPlotTe,                $
                        legendNames=Model, DoShowDist=0, IsOverPlot=IsOverPlot,     $
                        DoLegend=DoLegend,ymax_I=[900,35,1e6,25], DoLogT=1, linethick=5

           IsOverPlot = 1
           DoLegend   = 0
        endfor
        device,/close_file

        for iFile=0, nFileAdaptOne-1 do begin
           file_sim_adapt=files_adapt_one[iFile]

           compare_insitu_one, file_sim=file_sim_adapt, extra_plt_info=extra_plt_info,    $
                               UseTimePlotName=UseTimePlotName,                           $
                               CharSizeLocal=CharSizeLocal, DoPlotTe=DoPlotTe,            $
                               Model=Model, dir_obs=dir_obs, dir_plot=dirs_adapt[iFile],  $
                               DoSaveObs=0, DoLogT=1
        endfor
     endfor
  endif

  for i = 0, nSimFile-1 do begin
     file_sim     = files_sim(i)

     compare_insitu_one, file_sim=file_sim, extra_plt_info=extra_plt_info, $
                         UseTimePlotName=UseTimePlotName,                  $
                         CharSizeLocal=CharSizeLocal, DoPlotTe=DoPlotTe,   $
                         Model=Model, dir_obs=dir_obs, dir_plot=dir_plot,  $
                         DoSaveObs=1
  endfor
end

