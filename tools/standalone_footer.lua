print("[DeepHat v6.0 PRO] Suíte autônoma carregada com sucesso! Pressione [HOME] para abrir/fechar.")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "DeepHat v6.0 PRO",
        Text = "Interface carregada! Pressione [HOME] ou [RightShift] para abrir/fechar.",
        Duration = 5
    })
end)
