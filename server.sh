#!/bin/bash
# Указывает, что скрипт следует выполнять с использованием интерпретатора Bash
#данный скрипт собирает данные для мониторинга и собирает их в json формате




ncores=$(nproc)
# ncores получает значение количества процессорных ядер с помощью команды nproc

declare -A cpu_last
declare -A cpu_last_sum
declare -A cpu_result
declare -A ram_result
declare -A memory_result
# Объявляет два ассоциативных массива для хранения предыдущих значений

#сбор информации о нагрзке на ЦПУ (общая нагрузка и на каждое ядро)
read_cpu_usage() {

    # Начало определения функции read_cpu_usage, которая считывает текущие значения из /proc/stat и вычисляет загрузку процессора
    for ((i=0; i<2; i++)); do
      for ((j=0; j<=$ncores; j++)); do
          # Цикл, который будет обрабатывать все ядра процессора и общее использование процессора

          if [ $j -eq 0 ]; then
              # Если j равно 0

              cpu_now=($(head -n 1 /proc/stat))
              # Считывает первую строку из /proc/stat, которая содержит суммарную информацию обо всех ядрах

          else
              # В противном случае

              cpu_now=($(grep -m 1 "cpu$(($j-1)) " /proc/stat))
              # Считывает строку, содержащую информацию о конкретном ядре (например, "cpu0", "cpu1" и т.д.)

          fi

          cpu_sum="${cpu_now[@]:1}"
          # cpu_sum получает все колонки, кроме первой, которая содержит строку "cpu" или "cpuN"

          cpu_sum=$((${cpu_sum// /+}))
          # Заменяет пробелы знаком + и вычисляет сумму всех значений

          cpu_delta=$((cpu_sum - cpu_last_sum[$j]))
          # cpu_delta вычисляет разницу между текущей и предыдущей суммами всех счётчиков

          cpu_idle=$((cpu_now[4] - cpu_last[$j]))
          # cpu_idle вычисляет разницу в значении счётчика времени простоя между текущим и предыдущим чтением

          cpu_used=$((cpu_delta - cpu_idle))
          # Вычисляет время, затраченное на работу, как разницу между общей дельтой и дельтой времени простоя

          if [ $cpu_delta -ne 0 ]; then
              # Если cpu_delta не равен 0

              cpu_usage=$(echo "scale=1; 100 * $cpu_used / $cpu_delta" | bc)
              # Вычисляет процент использования процессора

          else
              # В противном случае

              cpu_usage=0
              # Устанавливает cpu_usage в 0 для избежания деления на ноль

          fi

          if [ $j -eq 0 ]; then
              # Если j равно 0

              cpu_result[$j]="{\"Total\": $cpu_usage,"
              # Выводит общую загрузку процессора
          elif [ $j -eq $ncores ]; then
              cpu_result[$j]="\"CPU$j\": $cpu_usage}"

          else
              # В противном случае

              cpu_result[$j]="\"CPU$j\": $cpu_usage, "
              # Выводит загрузку конкретного ядра
          fi

          cpu_last[$j]=${cpu_now[4]}
          # Обновляет массив cpu_last значением текущего времени простоя для ядра j

          cpu_last_sum[$j]=$cpu_sum
          # Обновляет массив cpu_last_sum значением текущей суммы всех счётчиков для ядра j
      done
      sleep 0.5 #спим после првой итерации
    done
    # Закрывает внутренний цикл, который проходит по всем ядрам
    #return $cpu_result
}
# Закрывает функцию read_cpu_usage

#Функция сбора информации об ОЗУ
read_ram_usage() {
  ram_total=$(free | awk '/^Mem:/ {print $2}')
  ram_used=$(free | awk '/^Mem:/ {print $3}')
  ram_avilable=$(free | awk '/^Mem:/ {print $7}')

  ram_result[0]=$ram_total
  ram_result[1]=$ram_used
  ram_result[2]=$ram_avilable

#  return $ram_result  #как оказалось результат выводить из функции не нужно (или нужно но оно и так прекрсно работает)
}

#Функция сбора информации об объеме памяти на диске (собирается инфа по каждому диску, потом ссумируется )
read_memory_usage(){
#    memory_total=$(df -m | awk '/^\/dev\// {sum += $2} END {print sum}') #размер по тому сколько примонтировано в общем
    memory_total=$(lsblk | awk '/^sd/ {sum += $4} END {print sum/1024}') #размер по дискам всего
    memory_used=$(df | awk '/^\/dev\// {sum += $3} END {print sum}')
    memory_avilable=$(df | awk '/^\/dev\// {sum += $4} END {print sum}')

    memory_result[0]=$memory_total
    memory_result[1]=$memory_used
    memory_result[2]=$memory_avilable

#     return $memory_result
}

#обявление пременных (при объявлении видимо доступны все переменные что были в функциях)
read_ram_usage
read_cpu_usage
read_memory_usage

result_for_cpu=""

for ((i=0; i<($ncores+1); i++))
do
  result_for_cpu="$result_for_cpu ${cpu_result[$i]}"
done

json_output=$(cat <<EOF
{
  "Token": "f643dd8211cf2ac6fcc286caecc39aa69e2a1d6d38bcb66dd78e399ab664991f",
  "data": {
      "RAM": {
          "Total": ${ram_result[0]},
          "Used": ${ram_result[1]},
          "Available": ${ram_result[2]}
      },
      "Memory":{
          "Total": ${memory_result[0]},
          "Used": ${memory_result[1]},
          "Available": ${memory_result[2]}
      },
      "CPU": $result_for_cpu
  }
}
EOF
)

url='https://b24.dev.skillline.ru/skillline.monitoring/api/monitoring.php'

curl -X POST -H "Content-Type: application/json" -d "$json_output" $url



