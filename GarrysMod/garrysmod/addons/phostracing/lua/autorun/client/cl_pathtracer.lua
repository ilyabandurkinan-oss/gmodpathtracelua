-- ВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВАЛЕРА
--  GMOD PATH TRACER на VisTraceDLL library. name V2 PhosTracing (Adaptive Edition)
-- ВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВВАЛЕРА!!!!

if SERVER then return end -- защита от "админов"

    -- хардкод DLL по названию TOO BAD!!
    if not pcall(require, "VisTrace-v0.13") then
        print("[PT] ОШИБКА: Модуль VisTrace не найден! Убедитесь, что бинарный файл установлен.")
        return
        end

        -- Параметры (ConVars)
        local cv_res_x    = CreateClientConVar("rt_res_x", "512", true, false, "Ширина рендера")
        local cv_res_y    = CreateClientConVar("rt_res_y", "512", true, false, "Высота рендера")
        local cv_samples  = CreateClientConVar("rt_spp", "64", true, false, "Сэмплов на пиксель")
        local cv_depth    = CreateClientConVar("rt_depth", "16", true, false, "Максимум отскоков (bounces)")
        local cv_rows     = CreateClientConVar("rt_rows", "16", true, false, "Рядов за кадр")
        local cv_hdri     = CreateClientConVar("rt_hdri", "drackenstein_quarry_4k", true, false, "Имя HDRI карты (без расширения)")

        -- Камера (теперь в ConVars)
        local cv_focal    = CreateClientConVar("rt_focal", "12", true, false, "Фокусное расстояние (мм)")
        local cv_sensor   = CreateClientConVar("rt_sensor", "24", true, false, "Высота сенсора (мм)")

        -- Адаптивный сэмплинг
        local cv_adaptive = CreateClientConVar("rt_adaptive", "1", true, false, "Включить адаптивный сэмплинг (1/0)")
        local cv_min_spp  = CreateClientConVar("rt_min_spp", "8", true, false, "Мин. сэмплов до проверки сходимости")
        local cv_thresh   = CreateClientConVar("rt_thresh", "0.03", true, false, "Порог шума (относительная ошибка)")

        local DEFAULT_MATERIAL = vistrace.CreateMaterial()
        local state = {
            rendering = false,
            done      = false,
            sample    = 0,
            row       = 0,
            startTime = 0,
            camPos    = Vector(),
            camAng    = Angle(),
            savePath  = "",
        }

        local accel, hdri, sampler, hdr, rt, rtMat = nil, nil, nil, nil, nil, nil
        local fb, fb_l, fb_l2, converged = {}, {}, {}, {}
        local initialized = false

        local sensorWidth, halfSensorWidth, halfSensorHeight
        local sensorWidthDivRes, sensorHeightDivRes, camConeAngle

        local function GetLuminance(col)
        return col[1] * 0.2126 + col[2] * 0.7152 + col[3] * 0.0722
        end

        local function ApplyResolution(w, h)
        local focal_mm = cv_focal:GetFloat()
        local sensor_mm = cv_sensor:GetFloat()

        sensorWidth        = sensor_mm * w / h
        halfSensorWidth    = sensorWidth / 2
        halfSensorHeight   = sensor_mm / 2
        sensorWidthDivRes  = sensorWidth / w
        sensorHeightDivRes = sensor_mm / h
        camConeAngle       = math.atan(sensor_mm / focal_mm / h)

        rt = GetRenderTargetEx(
            "PathTracer_" .. w .. "x" .. h, w, h, RT_SIZE_NO_CHANGE,
            MATERIAL_RT_DEPTH_SEPARATE, bit.bor(1, 256), 0, IMAGE_FORMAT_RGBA8888
        )
        rtMat = CreateMaterial("PathTracerMat_" .. w .. "x" .. h, "UnlitGeneric", {
            ["$basetexture"] = rt:GetName(),
        })
        hdr = vistrace.CreateRenderTarget(w, h, VisTraceRTFormat.RGBFFF)

        -- Инициализация буферов
        fb, fb_l, fb_l2, converged = {}, {}, {}, {}
        for i = 1, w * h do
            fb[i] = Vector(0, 0, 0)
            fb_l[i] = 0
            fb_l2[i] = 0
            converged[i] = false
            end
            end

            local function BuildScene()
            local props = ents.FindByClass("prop_*")
            accel = vistrace.CreateAccel(props, true)
            print("[PT] BVH собран: " .. #props .. " пропов + геометрия карты")
            end

            local function EnsureInit()
            local w = math.Clamp(cv_res_x:GetInt(), 64, 3840)
            local h = math.Clamp(cv_res_y:GetInt(), 64, 2160)
            local hdri_name = cv_hdri:GetString()

            if not initialized then
                sampler = vistrace.CreateSampler()
                initialized = true
                end

                -- Перезагружаем HDRI
                if not hdri or state.lastHDRI ~= hdri_name then
                    hdri = vistrace.LoadHDRI(hdri_name)
                    state.lastHDRI = hdri_name
                    if hdri then
                        print("[PT] HDRI загружен: " .. hdri_name)
                        else
                            print("[PT] ОШИБКА: Не удалось загрузить HDRI: " .. hdri_name .. ". Проверьте папку garrysmod/data/vistrace_hdris.")
                            return false
                            end
                            end

                            ApplyResolution(w, h)
                            return true
                            end

                            local function Power2Heuristic(a, b)
                            local a2, b2 = a * a, b * b
                            local d = a2 + b2
                            return d > 0 and a2 / d or 0
                            end

                            local function TracePixel(x, y)
                            local focal_mm = cv_focal:GetFloat()
                            local max_depth = cv_depth:GetInt()

                            local camX = halfSensorWidth  - sensorWidthDivRes  * (x + sampler:GetFloat())
                            local camY = halfSensorHeight - sensorHeightDivRes * (y + sampler:GetFloat())

                            local camDir = Vector(focal_mm, camX, camY)
                            camDir:Rotate(state.camAng)
                            camDir:Normalize()

                            local result = accel:Traverse(state.camPos, camDir, nil, nil, 0, camConeAngle)
                            if not result or result:HitSky() then
                                return hdri:GetPixel(camDir)
                                end

                                local colour = Vector()
                                local throughput = Vector(1, 1, 1)

                                for depth = 1, max_depth do
                                    local mat = result:Entity():IsValid() and result:Entity():GetBSDFMaterial() or DEFAULT_MATERIAL
                                    local sample = result:SampleBSDF(sampler, mat)
                                    if not sample then break end

                                        local delta = bit.band(LobeType.Delta, sample.lobe) ~= 0
                                        local reflection = bit.band(LobeType.Transmission, sample.lobe) == 0

                                        local origin = vistrace.CalcRayOrigin(
                                            result:Pos(),
                                                                              (result:FrontFacing() == reflection) and result:GeometricNormal() or -result:GeometricNormal()
                                        )

                                        -- Next Event Estimation (HDRI + MIS)
                                        if not delta then
                                            local envValid, envDir, envCol, envPdf = hdri:Sample(sampler)
                                            if envValid then
                                                local shadowRay = accel:Traverse(origin, envDir)
                                                if not shadowRay or shadowRay:HitSky() then
                                                    local mis = Power2Heuristic(envPdf, result:EvalPDF(mat, envDir))
                                                    colour = colour + throughput * result:EvalBSDF(mat, envDir) * envCol / envPdf * mis
                                                    end
                                                    end
                                                    end

                                                    throughput = throughput * sample.weight

                                                    -- Рулетка (Russian Roulette)
                                                    local rrProb = math.max(throughput[1], throughput[2], throughput[3])
                                                    if sampler:GetFloat() >= rrProb then break end
                                                        throughput = throughput / rrProb

                                                        result = accel:Traverse(origin, sample.scattered)
                                                        if not result or result:HitSky() then
                                                            local mis = delta and 1 or Power2Heuristic(sample.pdf, hdri:EvalPDF(sample.scattered))
                                                            colour = colour + throughput * hdri:GetPixel(sample.scattered) * mis
                                                            break
                                                            end
                                                            end

                                                            return colour
                                                            end

                                                            local function ACES(x)
                                                            return math.Clamp(x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14), 0, 1)
                                                            end

                                                            local function RenderRow(y)
                                                            local w = cv_res_x:GetInt()
                                                            local use_adaptive = cv_adaptive:GetBool()
                                                            local min_spp = cv_min_spp:GetInt()
                                                            local thresh = cv_thresh:GetFloat()

                                                            render.PushRenderTarget(rt)
                                                            for x = 0, w - 1 do
                                                                local idx = y * w + x + 1
                                                                local n = state.sample + 1

                                                                -- Если включен адаптивный сэмплинг и пиксель сходился — пропуск
                                                                if not (use_adaptive and converged[idx]) then
                                                                    local col = TracePixel(x, y)
                                                                    local acc = fb[idx] * ((n - 1) / n) + col * (1 / n)
                                                                    fb[idx] = acc

                                                                    -- Расчет дисперсии для адаптивного сэмплинга
                                                                    if use_adaptive then
                                                                        local l = GetLuminance(col)
                                                                        fb_l[idx] = fb_l[idx] + l
                                                                        fb_l2[idx] = fb_l2[idx] + l * l

                                                                        if n >= min_spp and (n % 4 == 0) then
                                                                            local mean = fb_l[idx] / n
                                                                            if mean > 0.001 then
                                                                                local variance = math.max(0, (fb_l2[idx] - (fb_l[idx] * fb_l[idx] / n)) / (n - 1))
                                                                                local stdError = math.sqrt(variance / n)
                                                                                if (stdError / mean) < thresh then
                                                                                    converged[idx] = true
                                                                                    end
                                                                                    end
                                                                                    end
                                                                                    end
                                                                                    end

                                                                                    local acc = fb[idx]
                                                                                    hdr:SetPixel(x, y, acc)

                                                                                    render.SetViewPort(x, y, 1, 1)
                                                                                    render.Clear(
                                                                                        ACES(acc[1]) ^ (1 / 2.2) * 255,
                                                                                                 ACES(acc[2]) ^ (1 / 2.2) * 255,
                                                                                                 ACES(acc[3]) ^ (1 / 2.2) * 255,
                                                                                                 255, true, true
                                                                                    )
                                                                                    end
                                                                                    render.PopRenderTarget()
                                                                                    end

                                                                                    local function FinishRender()
                                                                                    state.rendering = false
                                                                                    state.done = true
                                                                                    local elapsed = SysTime() - state.startTime

                                                                                    hdr:Tonemap(true)
                                                                                    local name = "pathtracer_" .. os.time() .. ".png"
                                                                                    hdr:Save(name)
                                                                                    state.savePath = "garrysmod/data/" .. name

                                                                                    print("╔════════════════════════════════════╗")
                                                                                    print(string.format("║  ГОТОВО: %d spp за %.1f сек", cv_samples:GetInt(), elapsed))
                                                                                    print("║  Сейв: " .. state.savePath)
                                                                                    print("╚════════════════════════════════════╝")
                                                                                    end

                                                                                    local function StartRender()
                                                                                    if state.rendering then return end
                                                                                        if not EnsureInit() then return end
                                                                                            BuildScene()

                                                                                            state.camPos = LocalPlayer():EyePos()
                                                                                            state.camAng = LocalPlayer():EyeAngles()
                                                                                            state.sample, state.row = 0, 0
                                                                                            state.done = false
                                                                                            state.startTime = SysTime()

                                                                                            local w = cv_res_x:GetInt()
                                                                                            local h = cv_res_y:GetInt()
                                                                                            local samples = cv_samples:GetInt()
                                                                                            local max_depth = cv_depth:GetInt()

                                                                                            for i = 1, w * h do
                                                                                                fb[i] = Vector(0, 0, 0)
                                                                                                fb_l[i] = 0
                                                                                                fb_l2[i] = 0
                                                                                                converged[i] = false
                                                                                                end

                                                                                                render.PushRenderTarget(rt)
                                                                                                render.Clear(0, 0, 0, 255, true, true)
                                                                                                render.PopRenderTarget()

                                                                                                state.rendering = true
                                                                                                print(string.format("[PT] Рендер начат: %dx%d, %d spp, %d bounces", w, h, samples, max_depth))
                                                                                                end

                                                                                                hook.Add("Think", "PT_Render", function()
                                                                                                if not state.rendering then return end

                                                                                                    local h = cv_res_y:GetInt()
                                                                                                    local target_samples = cv_samples:GetInt()
                                                                                                    local rows_per_frame = cv_rows:GetInt()

                                                                                                    for _ = 1, rows_per_frame do
                                                                                                        if state.row >= h then
                                                                                                            state.sample = state.sample + 1
                                                                                                            state.row = 0
                                                                                                            if state.sample >= target_samples then
                                                                                                                FinishRender()
                                                                                                                return
                                                                                                                end
                                                                                                                break
                                                                                                                end
                                                                                                                RenderRow(state.row)
                                                                                                                state.row = state.row + 1
                                                                                                                end
                                                                                                                end)

                                                                                                hook.Add("HUDPaint", "PT_HUD", function()
                                                                                                if not state.rendering and not state.done then return end

                                                                                                    local w_res = cv_res_x:GetInt()
                                                                                                    local h_res = cv_res_y:GetInt()
                                                                                                    local target_samples = cv_samples:GetInt()

                                                                                                    local sw, sh = ScrW(), ScrH()
                                                                                                    local scale = math.min(sw / w_res, sh / h_res) * 0.8
                                                                                                    local w, h = w_res * scale, h_res * scale
                                                                                                    local ox, oy = (sw - w) / 2, (sh - h) / 2

                                                                                                    surface.SetDrawColor(8, 10, 14, 235)
                                                                                                    surface.DrawRect(ox - 10, oy - 34, w + 20, h + 62)

                                                                                                    if rtMat then
                                                                                                        surface.SetMaterial(rtMat)
                                                                                                        surface.SetDrawColor(255, 255, 255)
                                                                                                        surface.DrawTexturedRect(ox, oy, w, h)
                                                                                                        end

                                                                                                        local prog = state.done and 1 or (state.sample + state.row / h_res) / target_samples
                                                                                                        local elapsed = SysTime() - state.startTime

                                                                                                        surface.SetDrawColor(35, 40, 50)
                                                                                                        surface.DrawRect(ox, oy + h + 8, w, 10)
                                                                                                        surface.SetDrawColor(232, 148, 42)
                                                                                                        surface.DrawRect(ox, oy + h + 8, w * prog, 10)

                                                                                                        local eta = prog > 0.01 and (elapsed / prog - elapsed) or 0
                                                                                                        draw.SimpleText(
                                                                                                            string.format("%s  %dx%d  |  sample %d/%d  |  %.1f%%  |  %s",
                                                                                                                          state.done and "RENDER COMPLETE" or "PATH TRACING...",
                                                                                                                          w_res, h_res, state.sample, target_samples, prog * 100,
                                                                                                                          state.done and ("saved: " .. state.savePath) or ("ETA ~" .. math.ceil(eta) .. "s")),
                                                                                                                        "DermaDefault", ox, oy - 26, Color(220, 225, 235)
                                                                                                        )
                                                                                                        end)

                                                                                                -- Консольные команды
                                                                                                concommand.Add("rt_render", StartRender)
                                                                                                concommand.Add("rt_stop", function()
                                                                                                state.rendering = false
                                                                                                print("[PT] Остановлено.")
                                                                                                end)
                                                                                                concommand.Add("rt_rebuild", function() EnsureInit() BuildScene() end)

                                                                                                print("=== GMod PathTracer (VisTrace) Загружен ===")
                                                                                                print("  rt_render - Начать рендер")
                                                                                                print("  rt_stop   - Остановить рендер")
                                                                                                print("  rt_rebuild- Пересобрать BVH сцены")
                                                                                                print("  rt_menu   - Открыть панель настроек")

                                                                                                -- Меню настроек (VGUI)
                                                                                                local function OpenPathTracerMenu()
                                                                                                local frame = vgui.Create("DFrame")
                                                                                                frame:SetSize(360, 560)
                                                                                                frame:Center()
                                                                                                frame:SetTitle("VisTrace PathTracer - Настройки V2")
                                                                                                frame:MakePopup()

                                                                                                local scroll = vgui.Create("DScrollPanel", frame)
                                                                                                scroll:Dock(FILL)

                                                                                                local function CreateSlider(parent, text, convar, min, max, decimals)
                                                                                                local slider = vgui.Create("DNumSlider", parent)
                                                                                                slider:Dock(TOP)
                                                                                                slider:DockMargin(10, 2, 10, 2)
                                                                                                slider:SetText(text)
                                                                                                slider:SetMinMax(min, max)
                                                                                                slider:SetDecimals(decimals or 0)
                                                                                                slider:SetConVar(convar)
                                                                                                return slider
                                                                                                end

                                                                                                local function CreateHeader(parent, text)
                                                                                                local lbl = vgui.Create("DLabel", parent)
                                                                                                lbl:Dock(TOP)
                                                                                                lbl:DockMargin(10, 8, 10, 2)
                                                                                                lbl:SetText(text)
                                                                                                lbl:SetFont("DermaDefaultBold")
                                                                                                lbl:SetTextColor(Color(232, 148, 42))
                                                                                                end

                                                                                                CreateHeader(scroll, "--- Разрешение и Проход ---")
                                                                                                CreateSlider(scroll, "Ширина (X)", "rt_res_x", 64, 3840, 0)
                                                                                                CreateSlider(scroll, "Высота (Y)", "rt_res_y", 64, 2160, 0)
                                                                                                CreateSlider(scroll, "Сэмплы (SPP)", "rt_spp", 1, 1024, 0)
                                                                                                CreateSlider(scroll, "Глубина (Bounces)", "rt_depth", 1, 32, 0)
                                                                                                CreateSlider(scroll, "Рядов за кадр", "rt_rows", 1, 64, 0)

                                                                                                CreateHeader(scroll, "--- Параметры Камеры ---")
                                                                                                CreateSlider(scroll, "Фокусное (мм)", "rt_focal", 10, 200, 1)
                                                                                                CreateSlider(scroll, "Сенсор (мм)", "rt_sensor", 10, 100, 1)

                                                                                                CreateHeader(scroll, "--- Адаптивный сэмплинг ---")
                                                                                                local check = vgui.Create("DCheckBoxLabel", scroll)
                                                                                                check:Dock(TOP)
                                                                                                check:DockMargin(10, 5, 10, 5)
                                                                                                check:SetText("Включить адаптивный сэмплинг")
                                                                                                check:SetConVar("rt_adaptive")

                                                                                                CreateSlider(scroll, "Мин. SPP до проверки", "rt_min_spp", 4, 128, 0)
                                                                                                CreateSlider(scroll, "Порог шума (Error)", "rt_thresh", 0.001, 0.1, 3)

                                                                                                CreateHeader(scroll, "--- Окружение (HDRI) ---")
                                                                                                local hdri_entry = vgui.Create("DTextEntry", scroll)
                                                                                                hdri_entry:Dock(TOP)
                                                                                                hdri_entry:DockMargin(10, 5, 10, 10)
                                                                                                hdri_entry:SetConVar("rt_hdri")

                                                                                                -- Кнопки
                                                                                                local btn_render = vgui.Create("DButton", scroll)
                                                                                                btn_render:Dock(TOP)
                                                                                                btn_render:DockMargin(10, 5, 10, 5)
                                                                                                btn_render:SetTall(30)
                                                                                                btn_render:SetText("НАЧАТЬ РЕНДЕР")
                                                                                                btn_render:SetIcon("icon16/camera.png")
                                                                                                btn_render.DoClick = function() RunConsoleCommand("rt_render") end

                                                                                                local btn_stop = vgui.Create("DButton", scroll)
                                                                                                btn_stop:Dock(TOP)
                                                                                                btn_stop:DockMargin(10, 0, 10, 5)
                                                                                                btn_stop:SetTall(25)
                                                                                                btn_stop:SetText("Остановить")
                                                                                                btn_stop:SetIcon("icon16/cancel.png")
                                                                                                btn_stop.DoClick = function() RunConsoleCommand("rt_stop") end

                                                                                                local btn_rebuild = vgui.Create("DButton", scroll)
                                                                                                btn_rebuild:Dock(TOP)
                                                                                                btn_rebuild:DockMargin(10, 0, 10, 10)
                                                                                                btn_rebuild:SetTall(25)
                                                                                                btn_rebuild:SetText("Обновить сцену (BVH)")
                                                                                                btn_rebuild:SetIcon("icon16/arrow_refresh.png")
                                                                                                btn_rebuild.DoClick = function() RunConsoleCommand("rt_rebuild") end
                                                                                                end

                                                                                                concommand.Add("rt_menu", OpenPathTracerMenu)
