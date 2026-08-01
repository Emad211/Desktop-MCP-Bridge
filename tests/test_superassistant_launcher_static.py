from pathlib import Path


def test_superassistant_proxy_uses_hidden_direct_node_launcher() -> None:
    script = (
        Path(__file__).parents[1] / "scripts" / "start-superassistant-proxy.ps1"
    ).read_text(encoding="utf-8")

    assert "Start-Process -FilePath $Node" in script
    assert "-WindowStyle Hidden" in script
    assert 'launch_method = "direct-node-hidden"' in script
    assert "superassistant-runtime" in script
    assert "npm install" in script
    assert "Start-Process -FilePath $Npx" not in script
    assert "-WindowStyle Minimized" not in script
