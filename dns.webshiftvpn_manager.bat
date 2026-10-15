Причина этой и предыдущей ошибки одна: при копировании кода из окна чата текстовый парсер воспринимает пары знаков доллара (`$...$`) как математические формулы и автоматически удаляет пробелы и переносы строк перед закрывающим знаком `$`. Из-за этого на строке 330 пропал перенос строки перед переменной `$connected`, и две команды склеились в одну (`...$null)$connected`).

Чтобы это больше не повторялось при копировании, в коде ниже перед каждым знаком `$` поставлены защитные скобки `($переменная)` или разделитель команд `;`. Парсер больше не сможет склеить строки или удалить нужные пробелы.

### Исправленный скрипт (`dns_manager.bat`)

Скопируйте код ниже, полностью замените им содержимое вашего `.bat`-файла (в кодировке **UTF-8**) и запустите:

```bat
@echo off >nul 2>&1
@echo off
chcp 65001 >nul 2>&1
setlocal
set "SELF_PATH=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  ";$f=($env:SELF_PATH);" ^
  ";$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($f)));" ^
  ";$runner='[Console]::OutputEncoding=[Text.Encoding]::UTF8;[Console]::InputEncoding=[Text.Encoding]::UTF8;try{;$f=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+($b64)+'''));;$t=[IO.File]::ReadAllText(($f),[Text.Encoding]::UTF8);if(($t.IndexOf([char]0xFFFD)) -ge 0){;$t=[IO.File]::ReadAllText(($f),[Text.Encoding]::GetEncoding(1251));};;$m=''#PS_''+''MAIN#'';;$i=($t.IndexOf(($m)));if(($i) -lt 0){throw ''Marker PS_MAIN not found''};[ScriptBlock]::Create(($t.Substring(($i)+($m.Length)))).Invoke();}catch{Write-Host (''[ERROR] ''+($_.ToString())) -ForegroundColor Red;Read-Host ''Press Enter to exit'';}';" ^
  ";$id=[Security.Principal.WindowsIdentity]::GetCurrent();" ^
  ";$p=New-Object Security.Principal.WindowsPrincipal(($id));" ^
  ";if(-not ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){" ^
  "  ;$ec=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($runner)));" ^
  "  Start-Process powershell.exe -ArgumentList ('-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -EncodedCommand '+($ec)) -Verb RunAs;" ^
  "}else{" ^
  "  Invoke-Expression ($runner);" ^
  "}"
exit /b

#PS_MAIN#
try {
    ;$OutputEncoding=[System.Text.Encoding]::UTF8;
    try {
        ;$Host.UI.RawUI.WindowTitle="Управление DNS и шифрованием DoH (Windows 11)";
    } catch {}

    ;$TargetDnsIp="31.31.207.68";
    ;$TargetTemplate="https://d.webshiftvpn.ru/dns-query";

    function Write-Ok {
        param([string]$Text="")
        Write-Host ($Text) -ForegroundColor Green;
    }

    function Write-Err {
        param([string]$Text="")
        Write-Host ($Text) -ForegroundColor Red;
    }

    function Read-GreenPrompt {
        param([string]$PromptText="")
        Write-Host ($PromptText) -ForegroundColor Green -NoNewline;
        ;$inputLine=Read-Host;
        if ([string]::IsNullOrWhiteSpace(($inputLine))) {
            return "";
        }
        return ($inputLine.Trim());
    }

    function Wait-ReturnToMenu {
        Write-Host "";
        Write-Host "Нажмите Enter, чтобы вернуться в главное меню..." -ForegroundColor Green -NoNewline;
        ;$null=Read-Host;
    }

    function Get-TargetAdapter {
        param([ValidateSet("Ethernet","WiFi")][string]$AdapterType)

        ;$allAdapters=@(Get-NetAdapter -ErrorAction SilentlyContinue);
        if (($allAdapters.Count) -eq 0) {
            return ($null);
        }

        ;$physical=@(($allAdapters) | Where-Object {
            (($_.InterfaceDescription) -notmatch "Virtual|VMware|VirtualBox|Hyper-V|TAP|TUN|VPN|WireGuard|Radmin|ZeroTier|Hamachi|Tailscale|Loopback|Bluetooth|WAN Miniport") -and
            (($_.Name) -notmatch "vEthernet|Bluetooth|Loopback")
        });

        if (($physical.Count) -eq 0) {
            ;$physical=($allAdapters);
        }

        if (($AdapterType) -eq "Ethernet") {
            ;$matched=@(($physical) | Where-Object {
                (($_.InterfaceType) -eq 6) -or
                (($_.PhysicalMediaType) -match "802\.3") -or
                (($_.MediaType) -match "802\.3") -or
                (($_.Name) -match "Ethernet|Сеть")
            });
        } else {
            ;$matched=@(($physical) | Where-Object {
                (($_.InterfaceType) -eq 71) -or
                (($_.PhysicalMediaType) -match "802\.11|Wireless") -or
                (($_.MediaType) -match "802\.11|Wireless") -or
                (($_.Name) -match "Wi-Fi|Беспроводная|WLAN|WiFi")
            });
        }

        if (($matched.Count) -eq 0) {
            return ($null);
        }

        ;$active=@(($matched) | Where-Object { (($_.Status) -eq "Up") });
        if (($active.Count) -gt 0) {
            return ($active[0]);
        }

        return ($matched[0]);
    }

    function Set-CustomDnsWithDoh {
        param([ValidateSet("Ethernet","WiFi")][string]$AdapterType)

        ;$adapter=Get-TargetAdapter -AdapterType ($AdapterType);
        if (($null) -eq ($adapter)) {
            Write-Err ("`n[ОШИБКА] Сетевой адаптер типа '"+($AdapterType)+"' не найден на этом компьютере.");
            return;
        }

        Write-Ok ("`n[*] Выбран адаптер: "+($adapter.Name)+" ("+($adapter.InterfaceDescription)+") [Статус: "+($adapter.Status)+"]");

        ;$guid=($adapter.InterfaceGuid.ToString().Trim());
        if (-not ($guid.StartsWith("{"))) {
            ;$guid="{"+($guid)+"}";
        }

        try {
            Write-Ok ("[*] Включение шифрования DNS по протоколу HTTPS ("+($TargetTemplate)+")...");

            if (-not (Get-Command "Add-DnsClientDohServerAddress" -ErrorAction SilentlyContinue)) {
                throw "В вашей версии Windows отсутствуют системные командлеты DNS-over-HTTPS.";
            }

            ;$existingDoh=@(Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue | Where-Object { (($_.ServerAddress) -eq ($TargetDnsIp)) });
            if (($existingDoh.Count) -gt 0) {
                Set-DnsClientDohServerAddress -ServerAddress ($TargetDnsIp) -DohTemplate ($TargetTemplate) -AllowFallbackToUdp ($false) -AutoUpgrade ($true) -ErrorAction Stop;
            } else {
                Add-DnsClientDohServerAddress -ServerAddress ($TargetDnsIp) -DohTemplate ($TargetTemplate) -AllowFallbackToUdp ($false) -AutoUpgrade ($true) -ErrorAction Stop;
            }

            ;$dohRegTargets=@(
                ("HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\"+($guid)+"\DohInterfaceSettings\Doh\"+($TargetDnsIp))
            );

            ;$profileDohBase=("HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\"+($guid)+"\DohProfileSettings\Doh");
            if (Test-Path ($profileDohBase)) {
                ;$subProfiles=@(Get-ChildItem -Path ($profileDohBase) -ErrorAction SilentlyContinue);
                foreach ($prof in ($subProfiles)) {
                    ;$dohRegTargets+=(Join-Path ($prof.PSPath) ($TargetDnsIp));
                }
            }

            foreach ($regPath in ($dohRegTargets)) {
                if (-not (Test-Path ($regPath))) {
                    New-Item -Path ($regPath) -Force -ErrorAction Stop | Out-Null;
                }
                New-ItemProperty -Path ($regPath) -Name "DohFlags" -Value ([uint64]1) -PropertyType QWord -Force -ErrorAction Stop | Out-Null;
                New-ItemProperty -Path ($regPath) -Name "DohTemplate" -Value ($TargetTemplate) -PropertyType String -Force -ErrorAction Stop | Out-Null;
            }
        } catch {
            Write-Err "[ОШИБКА ШИФРОВАНИЯ] Не удалось установить параметры шифрования DNS-over-HTTPS!";
            Write-Err ("Подробности: "+($_.Exception.Message));
            return;
        }

        try {
            Write-Ok ("[*] Установка предпочтительного IPv4 DNS-сервера "+($TargetDnsIp)+"...");
            Set-DnsClientServerAddress -InterfaceIndex ($adapter.ifIndex) -ServerAddresses @($TargetDnsIp) -ErrorAction Stop;

            ;$tcpProfileBase=("HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\"+($guid)+"\ProfileSpecificParameters");
            if (Test-Path ($tcpProfileBase)) {
                ;$tcpProfiles=@(Get-ChildItem -Path ($tcpProfileBase) -ErrorAction SilentlyContinue);
                foreach ($tp in ($tcpProfiles)) {
                    ;$prop=Get-ItemProperty -Path ($tp.PSPath) -Name "NameServer" -ErrorAction SilentlyContinue;
                    if (($null) -ne ($prop)) {
                        New-ItemProperty -Path ($tp.PSPath) -Name "NameServer" -Value ($TargetDnsIp) -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null;
                    }
                }
            }
            Write-Ok ("[+] Предпочтительный DNS "+($TargetDnsIp)+" установлен (дополнительный DNS оставлен пустым).");
        } catch {
            Write-Err ("[ОШИБКА DNS] Не удалось назначить IP-адрес DNS для '"+($adapter.Name)+"'!");
            Write-Err ("Подробности: "+($_.Exception.Message));
            return;
        }

        try {
            ;$checkDoh=@(Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue | Where-Object { (($_.ServerAddress) -eq ($TargetDnsIp)) });
            ;$mainRegPath=("HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\"+($guid)+"\DohInterfaceSettings\Doh\"+($TargetDnsIp));
            ;$checkReg=if (Test-Path ($mainRegPath)) { Get-ItemProperty -Path ($mainRegPath) -ErrorAction SilentlyContinue } else { ($null) };
            ;$checkIp=Get-DnsClientServerAddress -InterfaceIndex ($adapter.ifIndex) -AddressFamily IPv4 -ErrorAction SilentlyContinue;

            if ((($checkDoh.Count) -eq 0) -or (($checkDoh[0].DohTemplate) -ne ($TargetTemplate)) -or (($checkDoh[0].AllowFallbackToUdp) -ne ($false))) {
                throw "Глобальный шаблон DoH не прошел проверку после записи.";
            }
            if ((($null) -eq ($checkReg)) -or (($checkReg.DohFlags) -ne 1) -or (($checkReg.DohTemplate) -ne ($TargetTemplate))) {
                throw "Параметры шифрования интерфейса не сохранились в реестре Windows 11.";
            }
            if ((($null) -eq ($checkIp)) -or (($checkIp.ServerAddresses) -notcontains ($TargetDnsIp))) {
                throw ("Адрес DNS "+($TargetDnsIp)+" не закрепился на сетевом адаптере.");
            }

            Clear-DnsClientCache -ErrorAction SilentlyContinue;
            Write-Ok "[+] Шифрование DNS-over-HTTPS успешно включено и проверено!";
            Write-Ok ("    - Предпочтительный DNS : "+($TargetDnsIp));
            Write-Ok "    - DNS по HTTPS (DoH)   : Вкл. (шаблон вручную)";
            Write-Ok ("    - Шаблон DoH           : "+($TargetTemplate));
            Write-Ok "    - Возврат к откр.тексту: Выкл.";
            Write-Ok "[+] Кэш DNS очищен.";
        } catch {
            Write-Err "[ОШИБКА ПРОВЕРКИ ШИФРОВАНИЯ] Настройки были отправлены, но система не подтвердила включение шифрования!";
            Write-Err ("Причина: "+($_.Exception.Message));
        }
    }

    function Clear-CustomDns {
        Write-Ok "`nВыберите подключение, для которого нужно очистить настройки DNS:";
        Write-Ok "  [1] Проводной интернет (Ethernet)";
        Write-Ok "  [2] Беспроводная сеть (Wi-Fi)";
        Write-Ok "  [3] Очистить оба подключения сразу (Ethernet и Wi-Fi)";
        Write-Ok "  [0] Отмена и возврат в главное меню";

        ;$subChoice=Read-GreenPrompt "`nВаш выбор (0-3): ";

        ;$targets=switch ($subChoice) {
            "1" { @("Ethernet") }
            "2" { @("WiFi") }
            "3" { @("Ethernet","WiFi") }
            "0" { return }
            default {
                Write-Err ("[ОШИБКА] Неверный пункт меню '"+($subChoice)+"'. Введите цифру от 0 до 3.");
                return;
            }
        };

        foreach ($t in ($targets)) {
            ;$adapter=Get-TargetAdapter -AdapterType ($t);
            if (($null) -eq ($adapter)) {
                Write-Err ("[ОШИБКА] Адаптер типа '"+($t)+"' не найден.");
                continue;
            }

            try {
                Write-Ok ("`n[*] Сброс DNS для '"+($adapter.Name)+"' на автоматическое получение (DHCP)...");
                Set-DnsClientServerAddress -InterfaceIndex ($adapter.ifIndex) -ResetServerAddresses -ErrorAction Stop;

                ;$guid=($adapter.InterfaceGuid.ToString().Trim());
                if (-not ($guid.StartsWith("{"))) {
                    ;$guid="{"+($guid)+"}";
                }

                ;$dnscacheBase=("HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\"+($guid));
                ;$dohSubKeys=@("DohInterfaceSettings\Doh","DohProfileSettings\Doh");
                foreach ($sub in ($dohSubKeys)) {
                    ;$fullDohPath=Join-Path ($dnscacheBase) ($sub);
                    if (Test-Path ($fullDohPath)) {
                        Get-ChildItem -Path ($fullDohPath) -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue;
                    }
                }

                ;$tcpProfileBase=("HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\"+($guid)+"\ProfileSpecificParameters");
                if (Test-Path ($tcpProfileBase)) {
                    ;$tcpProfiles=@(Get-ChildItem -Path ($tcpProfileBase) -ErrorAction SilentlyContinue);
                    foreach ($tp in ($tcpProfiles)) {
                        Remove-ItemProperty -Path ($tp.PSPath) -Name "NameServer" -ErrorAction SilentlyContinue;
                    }
                }

                Write-Ok ("[+] Все ручные настройки DNS и шифрования для '"+($adapter.Name)+"' успешно сброшены.");
            } catch {
                Write-Err ("[ОШИБКА] Не удалось очистить настройки адаптера '"+($adapter.Name)+"': "+($_.Exception.Message));
            }
        }

        Clear-DnsClientCache -ErrorAction SilentlyContinue;
        Write-Ok "[+] Кэш DNS очищен.";
    }

    function Show-CurrentDnsStatus {
        Write-Ok "`n=========================================================================";
        Write-Ok "           ТЕКУЩИЙ СТАТУС DNS-ПОДКЛЮЧЕНИЙ И ШИФРОВАНИЯ (DoH)             ";
        Write-Ok "=========================================================================";

        ;$allGlobalDoh=@(Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue);
        ;$adapterTypes=@("Ethernet","WiFi");

        foreach ($t in ($adapterTypes)) {
            ;$adapter=Get-TargetAdapter -AdapterType ($t);
            if (($null) -eq ($adapter)) {
                Write-Err ("`n[-] Сетевой адаптер типа '"+($t)+"' не обнаружен на устройстве.");
                continue;
            }

            ;$guid=($adapter.InterfaceGuid.ToString().Trim());
            if (-not ($guid.StartsWith("{"))) {
                ;$guid="{"+($guid)+"}";
            }

            ;$ipConfig=Get-NetIPAddress -InterfaceIndex ($adapter.ifIndex) -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1;
            ;$localIp=if (($null) -ne ($ipConfig)) { ($ipConfig.IPAddress) } else { "Нет IPv4-адреса" };

            ;$tcpRegPath=("HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\"+($guid));
            ;$tcpRegData=if (Test-Path ($tcpRegPath)) { Get-ItemProperty -Path ($tcpRegPath) -ErrorAction SilentlyContinue } else { ($null) };
            ;$isManualDns=(($null) -ne ($tcpRegData)) -and (-not [string]::IsNullOrWhiteSpace(($tcpRegData.NameServer)));
            ;$dnsModeText=if ($isManualDns) { "Вручную (Статический)" } else { "Автоматически (DHCP от роутера/провайдера)" };

            Write-Ok "`n-------------------------------------------------------------------------";
            Write-Ok ("Тип подключения : "+($t));
            Write-Ok ("Имя адаптера    : "+($adapter.Name)+" ("+($adapter.InterfaceDescription)+")");
            Write-Ok ("Состояние       : "+($adapter.Status)+" | Скорость: "+($adapter.LinkSpeed)+" | MAC: "+($adapter.MacAddress));
            Write-Ok ("Локальный IPv4  : "+($localIp));
            Write-Ok ("Режим DNS       : "+($dnsModeText));

            ;$dnsClient=Get-DnsClientServerAddress -InterfaceIndex ($adapter.ifIndex) -AddressFamily IPv4 -ErrorAction SilentlyContinue;
            ;$servers=if (($null) -ne ($dnsClient)) { @($dnsClient.ServerAddresses) } else { @() };

            if (($servers.Count) -eq 0) {
                Write-Ok "Серверы DNS IPv4: Не назначены (адаптер не подключен к сети)";
                continue;
            }

            Write-Ok ("Серверы DNS IPv4: "+($servers -join ", "));

            foreach ($ip in ($servers)) {
                ;$globalEntry=@(($allGlobalDoh) | Where-Object { (($_.ServerAddress) -eq ($ip)) });
                ;$ifaceDohPath=("HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\"+($guid)+"\DohInterfaceSettings\Doh\"+($ip));
                ;$ifaceDohData=if (Test-Path ($ifaceDohPath)) { Get-ItemProperty -Path ($ifaceDohPath) -ErrorAction SilentlyContinue } else { ($null) };

                ;$flags=if ((($null) -ne ($ifaceDohData)) -and (($null) -ne ($ifaceDohData.DohFlags))) { [uint64]($ifaceDohData.DohFlags) } else { [uint64]0 };
                ;$template=if ((($null) -ne ($ifaceDohData)) -and (-not [string]::IsNullOrWhiteSpace(($ifaceDohData.DohTemplate)))) {
                    ($ifaceDohData.DohTemplate)
                } elseif ((($globalEntry.Count) -gt 0) -and (-not [string]::IsNullOrWhiteSpace(($globalEntry[0].DohTemplate)))) {
                    ($globalEntry[0].DohTemplate)
                } else {
                    "Не задан"
                };

                ;$isEncrypted=((($flags) -band 1) -eq 1) -or ((($flags) -band 2) -eq 2) -or ((($globalEntry.Count) -gt 0) -and (($globalEntry[0].AutoUpgrade) -eq ($true)));

                if ($isEncrypted) {
                    ;$fallbackAllowed=((($flags) -band 4) -eq 4) -or ((($globalEntry.Count) -gt 0) -and (($globalEntry[0].AllowFallbackToUdp) -eq ($true)));
                    ;$fallbackText=if ($fallbackAllowed) {
                        "Вкл. (Разрешен переход на открытый текст)"
                    } else {
                        "Выкл. (Строгое шифрование без открытого текста)"
                    };
                    Write-Ok ("  -> Сервер "+($ip)+" : ШИФРОВАНИЕ ВКЛЮЧЕНО (DNS-over-HTTPS)");
                    Write-Ok ("     Шаблон DoH            : "+($template));
                    Write-Ok ("     Возврат к откр. тексту: "+($fallbackText));
                } else {
                    Write-Err ("  -> Сервер "+($ip)+" : ШИФРОВАНИЕ ВЫКЛЮЧЕНО (Обычный открытый DNS без DoH)");
                }
            }
        }

        Write-Ok "`n-------------------------------------------------------------------------";
        Write-Ok ("[*] Проверка сетевой доступности DoH-сервера "+($TargetDnsIp)+" (порт 443 HTTPS)...");
        try {
            ;$tcp=New-Object System.Net.Sockets.TcpClient;
            ;$async=$tcp.BeginConnect(($TargetDnsIp),443,($null),($null));
            ;$connected=$async.AsyncWaitHandle.WaitOne(2500,($false));
            if (($connected) -and ($tcp.Connected)) {
                Write-Ok ("[+] Сервер "+($TargetDnsIp)+" успешно отвечает по протоколу HTTPS (порт 443 открыт).");
                ;$tcp.Close();
            } else {
                ;$tcp.Close();
                Write-Err ("[ОШИБКА] Сервер "+($TargetDnsIp)+" не ответил по порту 443 в течение 2.5 секунд.");
            }
        } catch {
            Write-Err ("[ОШИБКА] Не удалось проверить соединение с "+($TargetDnsIp)+" : "+($_.Exception.Message));
        }
    }

    while ($true) {
        Clear-Host;
        Write-Ok "=========================================================================";
        Write-Ok "               НАСТРОЙКА ЗАШИФРОВАННОГО DNS (WINDOWS 11)                 ";
        Write-Ok "=========================================================================";
        Write-Ok " Параметры подключения:";
        Write-Ok ("  * Предпочтительный DNS : "+($TargetDnsIp)+" (IPv4)");
        Write-Ok "  * DNS по HTTPS (DoH)   : Вкл. (шаблон вручную)";
        Write-Ok ("  * Шаблон DoH           : "+($TargetTemplate));
        Write-Ok "  * Возврат к откр.тексту: Выкл. (дополнительный DNS пуст)";
        Write-Ok "-------------------------------------------------------------------------";
        Write-Ok " ПАМЯТКА — КАКОЙ ВЫБОР ЛУЧШЕ СДЕЛАТЬ:";
        Write-Ok "  * Выберите [1], если ваш компьютер или ноутбук подключен к роутеру";
        Write-Ok "    сетевым кабелем (проводной интернет во вкладке Ethernet).";
        Write-Ok "  * Выберите [2], если вы подключаетесь к интернету без проводов";
        Write-Ok "    через домашнюю или рабочую беспроводную сеть (Wi-Fi).";
        Write-Ok "  * Выберите [3], если хотите отключить этот DNS и вернуть стандартные";
        Write-Ok "    автоматические настройки вашего интернет-провайдера.";
        Write-Ok "  * Выберите [4], чтобы посмотреть текущие настройки адаптеров,";
        Write-Ok "    активность шифрования DoH и проверить связь с сервером.";
        Write-Ok "=========================================================================";
        Write-Ok "  [1] Подключить DNS и шифрование для проводного интернета (Ethernet)";
        Write-Ok "  [2] Подключить DNS и шифрование для текущего Wi-Fi подключения";
        Write-Ok "  [3] Очистить текущие настройки DNS (для Ethernet или Wi-Fi)";
        Write-Ok "  [4] Показать статус текущих DNS-подключений и их шифрования";
        Write-Ok "  [0] Выход из программы";
        Write-Ok "=========================================================================";

        ;$choice=Read-GreenPrompt "`nВведите номер нужного пункта (0-4) и нажмите Enter: ";

        switch ($choice) {
            "1" {
                Set-CustomDnsWithDoh -AdapterType "Ethernet";
                Wait-ReturnToMenu;
            }
            "2" {
                Set-CustomDnsWithDoh -AdapterType "WiFi";
                Wait-ReturnToMenu;
            }
            "3" {
                Clear-CustomDns;
                Wait-ReturnToMenu;
            }
            "4" {
                Show-CurrentDnsStatus;
                Wait-ReturnToMenu;
            }
            "0" {
                Write-Ok "`nЗавершение работы скрипта...";
                [Environment]::Exit(0);
            }
            default {
                Write-Err ("`n[ОШИБКА] Неверный ввод '"+($choice)+"'. Пожалуйста, введите цифру от 0 до 4.");
                Start-Sleep -Seconds 2;
            }
        }
    }
} catch {
    Write-Host ("`n[НЕПРЕДВИДЕННАЯ ОШИБКА] "+($_.ToString())) -ForegroundColor Red;
    Write-Host "Нажмите Enter для выхода..." -ForegroundColor Green -NoNewline;
    ;$null=Read-Host;
}

```