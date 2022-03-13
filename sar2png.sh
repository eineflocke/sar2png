#!/bin/bash -u

if   [ $# -eq 0 ]; then
  hourbacks="1 24 840"
elif [ $# -ge 1 ]; then
  hourbacks="$*"
fi

servername="$(hostname) "

elems='u q d r S n F'

sardir='/var/log/sysstat'
nw_iface='ens3'
df_mount='/'

resultdir='/var/www/html/stat'
tempdir="${resultdir}/sar2png"

mkdir -p ${resultdir} ${tempdir}
cd ${tempdir}

gnupre="gnu.$$."

gnudatapre="${gnupre}data"
gnucmd="${gnupre}cmd.txt"
gnucmdtemplate="${gnupre}cmdtemplate.txt"
gnutemp="${gnupre}temp.txt"
gnuprint="${gnupre}print.txt"

find . -name 'gnu.*' -mtime +1 -delete
find . -name '?_20??????.txt' -mtime +36 -delete

for e in ${elems}; do

  if [ "${e}" = 'F' ]; then
    echo "$(date +'%H:%M:%S') $(df ${df_mount} | tail -n 1)" >> F_$(date +'%Y%m%d').txt
    continue
  fi

  for dback in $(seq 0 1); do

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

  unixmax=$((nows / secover * secover + secover))
  unixmin=$((unixmax - hourbackmax * 3600 - secover))

  xmax="$(date -d "@${unixmax}" +'%Y-%m-%dT%H:%M')"
  xmin="$(date -d "@${unixmin}" +'%Y-%m-%dT%H:%M')"

  ymdmax=$(date -d "${xmax}" +'%Y%m%d')

  ymdminminus=''
  if [ $(echo ${xmin} | cut -d'T' -f2) = "00:00" ]; then
    ymdminminus='1 day ago '
  fi
  ymdmin=$(date -d "${ymdminminus}${xmin}" +'%Y%m%d')

  for e in ${elems}; do

    case ${e} in

      # 'sar letter' )
      #   single element per letter:
      #     et='chart title';
      #     eu='unit displayed';
      #     es=y-axis maximum softlimit (blank for auto);
      #     eh=y-axis maximum hardlimit (blank for auto);
      #   can be multiple elements per letter:
      #     eas=('awk col number');
      #     efs=(division factor);
      #     ens=('element name displayed');
      #     ecs=('fill color');;

      'u' )
        et='cpu'; eu='[%]'; es=100; eh='';
        eas=('($3+$5)' '$5'); efs=(1 1); ens=('user' 'sys'); ecs=('#e69f00' '#56b4e9');;

      'q' )
        et='loadavg'; eu='[]'; es=0.1; eh='';
        eas=('$4' '$6'); efs=(1 1); ens=('1min' '15min'); ecs=('#009e73' '#f0e442');;

      'd' )
        et='disk'; eu='[MiB/s]'; es=0.1; eh='';
        eas=('$4' '$5'); efs=(1024 1024); ens=('read' 'write'); ecs=('#0072b2' '#d55e00');;

      'r' )
        et='mem'; eu='[MiB]'; es=1024; eh='';
        eas=('$4'); efs=(1024); ens=('used'); ecs=('#cc79a7');;

      'S' )
        et='memswap'; eu='[MiB]'; es=5000; eh='';
        eas=('($2+$3)' '$3'); efs=(1024 1024); ens=('free' 'used'); ecs=('#56b4e9' '#009e73');;

      'n' )
        et='nw'; eu='[MiB/s]'; es=0.1; eh='';
        eas=('$5' '$6'); efs=(1024 1024); ens=('receive' 'transfer'); ecs=('#666666' '#e69f00');;

      'F' )
        et='df'; eu='[GiB]'; es=120; eh='';
        eas=('$3' '$4'); efs=(1048576 1048576); ens=('free' 'used'); ecs=('#f0e442' '#0072b2');;

    esac

    gnuimage="sar_${backsuf}_${et}.png"

    cat << EOF > ${gnucmdtemplate}
reset
set terminal png transparent truecolor small size 480,120
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

    for ie in ${!eas[@]}; do

      ea=${eas[${ie}]}
      ef=${efs[${ie}]}
      en=${ens[${ie}]}
      ec=${ecs[${ie}]}

      gnudata="${gnudatapre}_${et}_${en}.txt"
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
          | awk '{if (($1 ~ /[0-9:]{8}/) && ($1 !~ /^00:00/ || NR > 5) && ($3 !~ /[A-Za-z]/)) print $1,'${ea}/${ef}';}' \
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

        cat << EOF2 >> ${gnucmdtemplate}
set label "${servername}${et}${etsuf} ${backsuf}\n${xmin} to ${xlatest}" at graph 0.02,0.94 tc rgb "gray40"
EOF2

      fi

      tac ${gnudata} > ${gnutemp}
      mv -f ${gnutemp} ${gnudata}

      gnuecho="'${gnudata}' using 1:2 \
        with filledcurves above y1=0 \
        title '${en}'"

      if [ ${ie} -eq 0 ]; then
        gnuecho="plot ${gnuecho} linecolor rgb '${ec}'"
      else
        gnuecho="     ${gnuecho} linecolor rgb '${ec}'"
      fi

      if [ ${#eas[@]} -ge 2 ] && [ ${ie} -lt $((${#eas[@]} - 1)) ]; then
        gnuecho="${gnuecho}, \\"
      fi

      echo ${gnuecho} >> ${gnucmdtemplate}

    done # for ie

    cat >> ${gnucmdtemplate} << EOF
set print "${gnuprint}"
print GPVAL_Y_MAX
EOF

    setyrange=''
    if   [ "${eh}" != '' ]; then
      setyrange="set yrange[0:${eh}]"
    fi
    cat ${gnucmdtemplate} | sed -e "s/SET_YRANGE/${setyrange}/" > ${gnucmd}

    if [ "${es}" != '' ]; then
      gnuplot ${gnucmd}
      gpmax=$(head -n 1 ${gnuprint})
      if [ $(echo "1000 * (${gpmax} - ${es})" | bc | sed -e 's/\..*//') -le 0 ]; then
        setyrange="set yrange[0:${es}]"
        cat ${gnucmdtemplate} | sed -e "s/SET_YRANGE/${setyrange}/" > ${gnucmd}
      fi
    fi

    gnuplot ${gnucmd}

    rm -f ${gnupre}*

  done # for e

  convert -append sar_${backsuf}_{cpu,loadavg,mem,memswap,df,disk,nw}.png sar_${backsuf}.png

done # for hourbackmax

convert +append sar_?-{hour,day,week}.png ${resultdir}/_sar2png.png

