#!/bin/bash -u

if   [ $# -eq 0 ]; then
  hourbacks="1 24 840"
elif [ $# -ge 1 ]; then
  hourbacks=$1
fi

image_w=480
image_h=120

servername="$(hostname) "

elems='u q d r S n F'

sardir='/var/log/sysstat'
nw_iface='ens3'
df_mount='/'

resultdir='/var/www/html/stat'
tempdir="${resultdir}/sar2png"

mkdir -p ${resultdir} ${tempdir}
cd ${tempdir}

find ?_20??????.txt -mtime +35 -delete

gnupre="gnu"

gnudatapre="${gnupre}data"
gnucmd="${gnupre}cmd.txt"
gnutemp="${gnupre}temp.txt"

rm -f ${gnupre}*

for e in ${elems}; do

  for dback in $(seq 0 1); do

    if [ "${e}" = 'F' ]; then
      break
    fi

    ymd="$(date -d "${dback} days ago" +%Y%m%d)"
    sar="${sardir}/sa${ymd}"

    if [ ! -f ${sar} ] && [ -f ${sar}.bz2 ]; then
      sarbase="$(basename ${sar})"
      cp -f ${sar}.bz2 .
      bunzip2 ${sarbase}.bz2
      rm -f ${sarbase}.bz2
    fi

    opt=''
    if [ "${e}" = 'n' ]; then
      opt="DEV --iface=${nw_iface}"
    fi

    sar -f ${sar} -${e} ${opt} > ${e}_${ymd}.txt

  done # for dback

  if [ "${e}" = 'F' ]; then
    echo "$(date +'%H:%M:%S') $(df ${df_mount} | tail -n 1)" >> F_$(date +'%Y%m%d').txt
  fi

done # for e

for hourbackmax in ${hourbacks}; do

  case ${hourbackmax} in
      1 ) secover=600;   backsuf='1-hour'; xtic='%H:%M';;
      3 ) secover=1800;  backsuf='3-hour'; xtic='%H:%M';;
      6 ) secover=3600;  backsuf='6-hour'; xtic='%H:%M';;
     24 ) secover=14400; backsuf='1-day';  xtic='%dT%H';;
     72 ) secover=43200; backsuf='3-day';  xtic='%dT%H';;
    168 ) secover=86400; backsuf='1-week'; xtic='%m-%d';;
    672 ) secover=86400; backsuf='4-week'; xtic='%m-%d';;
    840 ) secover=86400; backsuf='5-week'; xtic='%m-%d';;
      * ) echo "invalid hourbackmax?"; exit 1;;
  esac

  nows=$(date -d "${xspecified:=$(date +'%Y-%m-%dT%H:%M:%S')}" +%s)

  xmax=$((nows / secover * secover + secover))
  xmin=$((xmax - hourbackmax * 3600 - secover))

  xmax="$(date -d "@${xmax}" +'%Y-%m-%dT%H:%M')"
  xmin="$(date -d "@${xmin}" +'%Y-%m-%dT%H:%M')"

  ymdmax=$(date -d "${xmax}" +'%Y%m%d')
  ymdmin=$(date -d "${xmin}" +'%Y%m%d')

  for e in ${elems}; do

    case ${e} in

      # 'sar letter' )
      #   single element per letter:
      #     et='chart title'; eu='unit displayed'; ey='y-axis maximum softlimit (blank for auto)'; eh='y-axis maximum hardlimit (blank for auto)';
      #   can be multiple elements per letter:
      #     eps=('element col number'); efs=(division factor); ess=('element name displayed'); ecs=('fill color');;

      'u' )
        et='cpu'; eu='[%]'; ey='100'; eh='';
        eps=('($3+$5)' '$5'); efs=(1 1); ess=('user' 'sys'); ecs=('#e69f00' '#56b4e9');;

      'q' )
        et='loadavg'; eu='[]'; ey=''; eh='';
        eps=('$4' '$6'); efs=(1 1); ess=('1min' '15min'); ecs=('#009e73' '#f0e442');;

      'd' )
        et='disk'; eu='[MiB/s]'; ey=''; eh='';
        eps=('$4' '$5'); efs=(1024 1024); ess=('read' 'write'); ecs=('#0072b2' '#d55e00');;

      'r' )
        et='mem'; eu='[MiB]'; ey='1024'; eh='';
        eps=('$4'); efs=(1024); ess=('used'); ecs=('#cc79a7');;

      'S' )
        et='memswap'; eu='[MiB]'; ey='5000'; eh='';
        eps=('($2+$3)' '$3'); efs=(1024 1024); ess=('free' 'used'); ecs=('#56b4e9' '#009e73');;

      'n' )
        et='nw'; eu='[KiB/s]'; ey=''; eh='';
        eps=('$5' '$6'); efs=(1 1); ess=('receive' 'transfer'); ecs=('#666666' '#e69f00');;

      'F' )
        et='df'; eu='[GiB]'; ey='120'; eh='';
        eps=('$3' '$4'); efs=(1048576 1048576); ess=('free' 'used'); ecs=('#f0e442' '#0072b2');;

    esac

    gnuimage="sar_${backsuf}_${et}.png"

    cat << EOF > ${gnucmd}
reset
set terminal png transparent truecolor small size ${image_w},${image_h}
set output '${gnuimage}'
set margins screen 0.090, screen 0.970, screen 0.120, screen 0.960 # l,r,b,t
set termoption enhanced
set grid
set style fill transparent solid 0.6
set xdata time
set timefmt '%Y-%m-%dT%H:%M'
set xrange['${xmin}':'${xmax}']
SET_YRANGE
set key top right reverse horizontal tc rgb "gray40"
set xtics format "${xtic}" offset 0,graph 0.03
set label '${eu}' at screen 0.01,0.5 rotate by 90 center
EOF

    valuemax=-9999999

    for ie in ${!eps[@]}; do

      es=${ess[${ie}]}
      ep=${eps[${ie}]}
      ef=${efs[${ie}]}
      ec=${ecs[${ie}]}

      gnudata="${gnudatapre}_${et}_${es}.txt"
      rm -f ${gnudata}

      for f in $(find ${e}_20??????.txt | sort | tac); do

        ymd8=$(echo ${f} | sed -e "s;${e}_;;" | sed -e 's;\.txt;;')

        if [ ${ymd8} -lt ${ymdmin} ]; then break; fi
        if [ ${ymd8} -gt ${ymdmax} ]; then continue; fi

        y4=$(echo ${ymd8} | cut -c1-4)
        m2=$(echo ${ymd8} | cut -c5-6)
        d2=$(echo ${ymd8} | cut -c7-8)

        ymdp0="${y4}-${m2}-${d2}"
        ymdp1="$(date -d "1 day ${ymdp0}" +'%Y-%m-%d')"

        tac ${f} \
          | awk '{if (($1 ~ /[0-9:]{8}/) && ($1 !~ /^00:00/ || NR > 5) && ($3 !~ /[A-Za-z]/)) print $1,'${ep}/${ef}';}' \
          | sed -e "s/^00:00/${ymdp1}T00:00/" \
          | sed -e "s/^\([0-9:]\{5\}\)/${ymdp0}T\1/" \
          >> ${gnudata}

      done # for f

      if [ ${ie} -eq 0 ]; then

        xlatest="$(head -n 1 ${gnudata} | cut -d' ' -f1 | cut -c01-16)"
        if [ $(date -d "${xmax}" +%s) -lt $(date -d "${xlatest}" +%s) ]; then
          xlatest=${xmax}
        fi

        etsuf=''
        if   [ "${e}" = 'n' ]; then
          etsuf=":${nw_iface}"
        elif [ "${e}" = 'F' ]; then
          etsuf=":${df_mount}"
        fi

        cat << EOF2 >> ${gnucmd}
set label "${servername}${et}${etsuf} ${backsuf}\n${xmin} to ${xlatest}" at graph 0.02,0.94 tc rgb "gray40"
EOF2

      fi

      tac ${gnudata} > ${gnutemp}
      mv -f ${gnutemp} ${gnudata}

      valuemax=$(cat ${gnudata} | awk 'BEGIN {a = '${valuemax}';} {if (a < $2) a = $2;} END {print a;}')

      gnuecho="'${gnudata}' using 1:2 \
        with filledcurves above y1=0 \
        title '${es}'"

      if [ ${ie} -eq 0 ]; then
        gnuecho="plot ${gnuecho} linecolor rgb '${ec}'"
      else
        gnuecho="     ${gnuecho} linecolor rgb '${ec}'"
      fi

      if [ ${#eps[@]} -ge 2 -a ${ie} -lt $((${#eps[@]} - 1)) ]; then
        gnuecho="${gnuecho}, \\"
      fi

      echo ${gnuecho} >> ${gnucmd}

    done # for ie

    if   [ "${eh}" != '' ]; then
      setyrange="set yrange[0:${eh}]"
    elif [ "${ey}" != '' ]; then
      valuemax=$(echo ${valuemax} | sed -e 's/\..*//')
      if [ ${ey} -lt ${valuemax} ]; then
        setyrange="set yrange[0:${valuemax}]"
      else
        setyrange="set yrange[0:${ey}]"
      fi
    else
      setyrange=''
    fi

    cat ${gnucmd} | sed -e "s/SET_YRANGE/${setyrange}/" > ${gnutemp}
    mv -f ${gnutemp} ${gnucmd}

    gnuplot ${gnucmd}

    rm -f ${gnupre}*

  done # for e

  convert -append sar_${backsuf}_{cpu,loadavg,mem,memswap,df,disk,nw}.png sar_${backsuf}.png

done # for hourbackmax

convert +append sar_?-{hour,day,week}.png ${resultdir}/_sar2png.png

