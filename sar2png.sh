#!/bin/bash -u

image_w=500
image_h=150
servername="$(hostname) "
sardir='/var/log/sysstat'
nw_iface='ens3'
resultdir='/var/www/html/stat'
tempdir="${resultdir}/sar"

mkdir -p ${resultdir} ${tempdir}

for dback in 1 0; do

  ymd="$(date -d "${dback} days ago" +%Y%m%d)"
  sar="${sardir}/sa${ymd}"

  sar -f ${sar} -u > ${tempdir}/u_${ymd}.txt
  sar -f ${sar} -q > ${tempdir}/q_${ymd}.txt
  sar -f ${sar} -d > ${tempdir}/d_${ymd}.txt
  sar -f ${sar} -r > ${tempdir}/r_${ymd}.txt
  sar -f ${sar} -n DEV --iface=${nw_iface} > ${tempdir}/n_${ymd}.txt

done # for dback

gnudatapre="${tempdir}/gnudata"
gnuplot="${tempdir}/gnuplot.txt"
gnutemp="${tempdir}/gnutemp.txt"

rm -f ${gnudatapre}* ${gnuplot} ${gnutemp}

for hourbackmax in 3 24 168; do

  case ${hourbackmax} in
      3 ) secover=1800;  backsuf='3-hour'; xtic='%H:%M';;
     24 ) secover=14400; backsuf='1-day';  xtic='%dT%H';;
    168 ) secover=86400; backsuf='7-day';  xtic='%dT%H';;
  esac

  nows=$(date +%s)
  xmax=$((nows / secover * secover + secover))
  xmin=$((xmax - hourbackmax * 3600))

  xmax="$(date -d "@${xmax}" +'%Y-%m-%dT%H:%M')"
  xmin="$(date -d "@${xmin}" +'%Y-%m-%dT%H:%M')"
  
  ymdmin=$(date -d "${xmin}" +'%Y%m%d')

  linetype=1

  for e in u q d r n; do

    case ${e} in

      'u' ) et='cpu'; eu='[%]'; ey='100';
            eps=(3 5); efs=(1 1); ess=('user' 'sys');;

      'q' ) et='loadavg'; eu='[]'; ey='';
            eps=(4 6); efs=(1 1); ess=('1min' '15min');;

      'd' ) et='disk'; eu='[MiB/s]'; ey='';
            eps=(4 5); efs=(1024 1024); ess=('read' 'write');;

      'r' ) et='mem'; eu='[MiB]'; ey='1024';
            eps=(4); efs=(1024); ess=('used');;

      'n' ) et='nw'; eu='[KiB/s]'; ey='';
            eps=(5 6); efs=(1 1); ess=('receive' 'transfer');;

    esac

    gnuimage="${tempdir}/sar_${backsuf}_${et}.png"

    if [ "${ey}" != '' ]; then
      ey="set yrange[0:${ey}]"
    fi

    cat << EOF > ${gnuplot}
reset
set terminal png transparent truecolor small size ${image_w},${image_h}
set output '${gnuimage}'
set margins screen 0.090, screen 0.964, screen 0.110, screen 0.970 # lrbt
set termoption enhanced
set colorsequence podo
set grid
set style fill transparent solid 0.7
set xdata time
set timefmt '%Y-%m-%dT%H:%M'
set xrange['${xmin}':'${xmax}']
${ey}
set key top right reverse horizontal tc rgb "gray40"
set xtics time format "${xtic}" offset 0,graph 0.03
set label '${eu}' at screen 0.01,0.5 rotate by 90 center
EOF

    for ie in ${!eps[@]}; do

      es=${ess[${ie}]}
      ep=${eps[${ie}]}
      ef=${efs[${ie}]}

      gnudata="${gnudatapre}_${et}_${es}.txt"
      rm -f ${gnudata}

      linetype=$((linetype + 1))

      for f in $(ls -r ${tempdir}/${e}_20??????.txt); do

        ymd8=$(echo ${f} | sed -e "s;${tempdir}/${e}_;;" | sed -e 's;\.txt;;')

        if [ ${ymd8} -lt ${ymdmin} ]; then break; fi

        y4=$(echo ${ymd8} | cut -c1-4)
        m2=$(echo ${ymd8} | cut -c5-6)
        d2=$(echo ${ymd8} | cut -c7-8)

        ymdp0="${y4}-${m2}-${d2}"
        ymdp1="$(date -d "1 day ${ymdp0}" +'%Y-%m-%d')"

        tac ${f} \
          | awk '$1 ~ /[0-9:]{8}/' \
          | awk '$3 !~ /[A-Za-z]/' \
          | awk "{print \$1,\$${ep}/${ef}}" \
          | sed -e "s/^00:00/${ymdp1}T00:00/" \
          | sed -e "s/^\([0-9:]\{5\}\)/${ymdp0}T\1/" \
          >> ${gnudata}

      done # for f

      if [ ${ie} -eq 0 ]; then

        xlatest="$(head -n 1 ${gnudata} | cut -d' ' -f1)"
        xlatest="$(date -d "${xlatest}" +'%Y-%m-%dT%H:%M')"

        et2=''
        if [ ${e} = 'n' ]; then
          et2=":${nw_iface}"
        fi

        cat << EOF2 >> ${gnuplot}
set label "${servername}${et}${et2} ${backsuf}\n${xmin} to ${xlatest}" at graph 0.02,0.94 tc rgb "gray40"
EOF2

      fi

      tac ${gnudata} > ${gnutemp}
      mv ${gnutemp} ${gnudata}

      #max=$(cat ${gnudata} | awk 'BEGIN {m =-1000000} {if (m < $2) m = $2} END {print m}')
      #min=$(cat ${gnudata} | awk 'BEGIN {m = 1000000} {if (m > $2) m = $2} END {print m}')

      gnuecho="'${gnudata}' using 1:2 \
        with filledcurves above y1=0 \
        title '${es}' \
        linetype ${linetype}"

      if [ ${ie} -eq 0 ]; then
        gnuecho="plot ${gnuecho}"
      else
        gnuecho="     ${gnuecho}"
      fi

      if [ ${#eps[@]} -ge 2 -a ${ie} -lt $((${#eps[@]} - 1)) ]; then
        gnuecho="${gnuecho}, \\"
      fi

      echo ${gnuecho} >> ${gnuplot}

    done # for ie

      gnuplot ${gnuplot}

      rm -f ${gnudatapre}* ${gnuplot} ${gnutemp}

  done # for e

  convert -append ${tempdir}/sar_${backsuf}_*.png ${resultdir}/sar_${backsuf}.png

done # for hourbackmax

convert +append ${resultdir}/sar_{3-hour,1-day,7-day}.png ${resultdir}/index.png

