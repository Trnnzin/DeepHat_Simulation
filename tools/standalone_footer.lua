print("[DeepHat v7.0 PRO] Suíte autônoma carregada com sucesso! Pressione [HOME] ou [RightShift] para abrir/fechar.")

-- Verificação de integridade da GUI
if DashboardGUI and not DashboardGUI.GetScreenGui() then
    warn("[DeepHat Standalone] Interface não detectada no footer. Invocando DashboardGUI.Create()...")
    local ok, err = pcall(function() DashboardGUI.Create() end)
    if not ok then
        warn("[DeepHat Standalone FATAL] Falha ao criar GUI no fallback: " .. tostring(err))
    end
end

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v7.0 PRO",
        Text = "Interface carregada! Pressione [HOME] ou [RightShift] para abrir/fechar.",
        Duration = 5
    })
end)
