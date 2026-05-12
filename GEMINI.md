to ma byc projekt do portfolio do szukania pracy jako cloud engineer, wiec chcemy zachowac najnowsze standardy branzowe
pierwszy projekt z portfolio to ten (sklonowalem to repo jako punkt wyjscia do tego projektu):
https://github.com/dbembnista1/aws-car-prices-tracker
w tym projekcie chce usprawnic gh actions - terraform ma miec tez swoj CI/CD na remote backendzie do team collaboration
gh actions musza byc poprawnie zrobione pod kolaboracje - czyli na zasadzie pull requestow i chce pracowac na features branchasz zeby po prostu uczyc sie githuba
celem glownym jest przejscie z ec2 na kontenery - ecs z fargate zeby zastapic web server na ec2
zawsze pytaj zanim wezmiesz sie za kod, nie wyrywak sie z kodem, pierw chce miec zawsze koncepcyjna wiedze co zmienisz


Outline zadan do wykonania:

  Faza 1: Fundamenty i Kolaboracja (Remote State)
  Zanim zaczniemy duże zmiany, musimy przejść na standardy "team collaboration".
   1. Infrastruktura pod Remote State: Utworzenie S3 Bucket i DynamoDB (do blokowania stanu) w AWS.
   2. Migracja stanu: Konfiguracja bloku backend "s3" i przeniesienie lokalnego pliku terraform.tfstate do chmury.

  Faza 2: Profesjonalny Pipeline CI/CD dla Terraform i Lambd
  Wdrożenie przepływu pracy opartego na Pull Requestach (PR) dla kluczowych komponentów.
   1. Workflow Terraform CI: Automatyczne sprawdzanie kodu (fmt, validate) oraz generowanie terraform plan przy każdym PR do main.
   2. Workflow Terraform CD: Automatyczny terraform apply po zmergowaniu zmian do gałęzi main.
   3. Workflow Lambdas: Aktualizacja akcji dla Lambd, aby walidacja/testy odbywały się na PR, a wdrożenie tylko po mergu. 
   *(Uwaga: Pomijamy aktualizację CI/CD dla EC2, ponieważ zostanie ono zastąpione przez ECS w Fazie 4).*

  Faza 3: Konteneryzacja i ECR
  Przygotowanie aplikacji Express do pracy w kontenerze.
   1. Dockerfile: Stworzenie obrazu dla aplikacji w src/express.
   2. Repozytorium ECR: Utworzenie Amazon ECR przez Terraform.
   3. App Pipeline: GitHub Action budujący i wypychający obraz Dockerowy do ECR po zmianach w kodzie aplikacji.

  Faza 4: Migracja na ECS z Fargate
  Zastąpienie obecnego serwera EC2 nowoczesną infrastrukturą kontenerową.
   1. Moduł ECS: Definicja klastra, Task Definition i serwisu Fargate.
   2. Load Balancer (ALB): Konfiguracja ALB do kierowania ruchu na kontenery.
   3. Networking: Dostosowanie grup bezpieczeństwa (Security Groups) i VPC pod ECS.

  Faza 5: Sprzątanie i Optymalizacja
   1. Usunięcie EC2: Wyłączenie i usunięcie starych zasobów z modułu compute.
   2. Dokumentacja: Opisanie nowej architektury w README jako gotowego projektu do portfolio.

   Chcemy pracowac tak jak w teamie developerskim - czyli pamietac zeby uzywac branchy!!!
   
  # Środowisko i Terminal
- ZAWSZE używaj składni PowerShell. Pracujemy w środowisku Windows.
- Nigdy nie używaj narzędzi linuksowych takich jak `sed`, `awk`, `grep`, `cat`, `ls`, `cp`, `rm`.
- Do edycji plików z poziomu terminala używaj natywnych poleceń PowerShell, np. `Get-Content`, `Set-Content`, `Add-Content` lub `Out-File`.
- Do wyszukiwania tekstu używaj `Select-String`.
- Pamiętaj, że starsze wersje PowerShell nie obsługują operatora `&&` tak jak Bash – jeśli łączysz komendy, używaj `;` (średnika) lub upewnij się, że korzystasz ze składni PowerShell 7+.