package logic

import (
	"context"
	"mall/common/cryptx"
	"mall/service/user/model"
	"mall/service/user/rpc/internal/svc"
	"mall/service/user/rpc/types/user"

	"github.com/zeromicro/go-zero/core/logx"
	"google.golang.org/grpc/status"
)

type RegisterLogic struct {
	ctx    context.Context
	svcCtx *svc.ServiceContext
	logx.Logger
}

func NewRegisterLogic(ctx context.Context, svcCtx *svc.ServiceContext) *RegisterLogic {
	return &RegisterLogic{
		ctx:    ctx,
		svcCtx: svcCtx,
		Logger: logx.WithContext(ctx),
	}
}

func (l *RegisterLogic) Register(in *user.RegisterRequest) (*user.RegisterResponse, error) {
	//judge dup
	_, err := l.svcCtx.UserModel.FindOneByMobile(l.ctx, in.Mobile)
	if err == nil {
		return nil, status.Error(100, "user existed")
	}
	if err == model.ErrNotFound {
		// construct
		newUser := model.User{
			Name:     in.Name,
			Gender:   uint64(in.Gender),
			Mobile:   in.Mobile,
			Password: cryptx.PasswordEncrypt(l.svcCtx.Config.Salt, in.Password),
		}
		// dial DB sql handle it
		res, err := l.svcCtx.UserModel.Insert(l.ctx, &newUser)
		if err != nil {
			return nil, status.Error(500, err.Error())
		}
		id, err := res.LastInsertId()
		if err != nil {
			return nil, status.Error(500, err.Error())
		}
		newUser.Id = uint64(id)
		return &user.RegisterResponse{
			Id:     int64(newUser.Id),
			Name:   newUser.Name,
			Gender: int64(newUser.Gender),
			Mobile: newUser.Mobile,
		}, nil
	}
	return nil, status.Error(500, err.Error())
}
